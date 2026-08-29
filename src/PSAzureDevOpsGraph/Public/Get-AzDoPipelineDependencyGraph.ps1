Set-StrictMode -Version 3.0

function Get-AzDoPipelineDependencyGraph {
    <#
    .SYNOPSIS
        The dependency graph of a project's pipelines, the YAML they reference,
        and the repositories that YAML lives in.

    .DESCRIPTION
        Read-only. Answers "if I change this template, which pipelines break?"

        Every definition's YAML is the root of a walk. Each file is parsed, its
        references resolved, and resolved template targets are walked in turn.
        A file is walked once however many times it is reached, so a template
        that includes itself, or a pair that include each other, terminates:
        the second arrival adds the edge and stops. A diamond likewise yields
        one node and two edges rather than a duplicated subtree.

        References that do not resolve become edges of kind 'unresolved'
        carrying the reason. They are the point of the tool. A graph that
        silently dropped them would render a broken pipeline identical to a
        working one.

    .PARAMETER Organisation
        The Azure DevOps organisation name.

    .PARAMETER Project
        The project name.

    .PARAMETER PipelineName
        Limit the walk to these definitions. All definitions by default.

    .EXAMPLE
        Get-AzDoPipelineDependencyGraph -Organisation contoso -Project Platform

    .OUTPUTS
        An object matching fixture/graph.schema.json: version, organisation,
        project, generatedBy, nodes, edges.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Organisation,
        [Parameter(Mandatory)][string] $Project,
        [Parameter()][string[]] $PipelineName
    )

    $repos = @(Get-AzDoRepository -Organisation $Organisation -Project $Project)
    Write-Verbose ("{0} repositories" -f $repos.Count)

    $pipelines = @(Get-AzDoPipeline -Organisation $Organisation -Project $Project)
    if ($PipelineName) { $pipelines = @($pipelines | Where-Object { $_.Name -in $PipelineName }) }
    Write-Verbose ("{0} pipeline definitions" -f $pipelines.Count)

    # ---- what exists, so a missing file is a reason and not a phantom -----
    $inventory = @{}
    foreach ($repo in $repos) {
        $set = New-Object 'System.Collections.Generic.HashSet[string]'

        if ($repo.IsEmpty) {
            # An empty repository has no default branch; asking for its items
            # is an error, not an empty list. It is still a node.
            Write-Verbose ("{0} is empty; no items to list" -f $repo.Name)
            $inventory[$repo.Name] = $set
            continue
        }

        try {
            $items = Invoke-AzDoRestMethod -Organisation $Organisation -Project $Project `
                        -Resource ('git/repositories/{0}/items' -f $repo.Id) `
                        -Query @{ recursionLevel = 'Full' }

            foreach ($item in $items.value) {
                $isFolder = ($item.PSObject.Properties.Name -contains 'isFolder') -and $item.isFolder
                if ($isFolder) { continue }
                $null = $set.Add((ConvertTo-AzDoRepositoryRelativePath -Path ([string]$item.path)).ToLowerInvariant())
            }
        }
        catch {
            Write-Warning ("Could not list items in repository '{0}': {1}" -f $repo.Name, $_.Exception.Message)
        }

        $inventory[$repo.Name] = $set
    }

    # ---- node and edge accumulation --------------------------------------
    $nodes = [ordered]@{}
    $edges = New-Object System.Collections.Generic.List[object]

    $repoNodeId     = { param($n) 'repo:' + $n }
    $pipelineNodeId = { param($n) 'pipeline:' + $n }
    $yamlNodeId     = { param($r, $p) 'yaml:' + $r + '/' + $p }

    foreach ($repo in $repos) {
        $id = & $repoNodeId $repo.Name
        $nodes[$id] = [ordered]@{ id = $id; kind = 'repo'; name = $repo.Name }
    }

    foreach ($pipeline in $pipelines) {
        $id = & $pipelineNodeId $pipeline.Name
        $nodes[$id] = [ordered]@{ id = $id; kind = 'pipeline'; name = $pipeline.Name }
    }

    $addYamlNode = {
        param($RepoName, $PathInRepo)
        $id = & $yamlNodeId $RepoName $PathInRepo
        if (-not $nodes.Contains($id)) {
            $nodes[$id] = [ordered]@{
                id   = $id
                kind = 'yaml'
                name = $PathInRepo
                repo = $RepoName
                path = 'repos/' + $RepoName + '/' + $PathInRepo
            }
        }
        return $id
    }

    $addEdge = {
        param($From, $To, $Kind, $Ref, $RefKind, $Alias, $Reason)

        $edge = [ordered]@{ from = $From; to = $To; kind = $Kind }
        if ($Ref)     { $edge['ref']     = $Ref }
        if ($RefKind) { $edge['refKind'] = $RefKind }
        if ($Alias)   { $edge['alias']   = $Alias }
        if ($Reason)  { $edge['reason']  = $Reason }
        $edges.Add($edge)
    }

    # ---- the walk ---------------------------------------------------------
    $visited = New-Object 'System.Collections.Generic.HashSet[string]'
    $queue   = New-Object System.Collections.Generic.Queue[object]
    $content = @{}

    foreach ($pipeline in $pipelines) {
        if (-not $pipeline.YamlPath -or -not $pipeline.RepositoryName) {
            Write-Verbose ("'{0}' has no YAML configuration; no definition edge" -f $pipeline.Name)
            continue
        }

        $yamlId = & $addYamlNode $pipeline.RepositoryName $pipeline.YamlPath
        & $addEdge (& $pipelineNodeId $pipeline.Name) $yamlId 'definition' $null $null $null $null

        $queue.Enqueue([pscustomobject]@{ Repository = $pipeline.RepositoryName; Path = $pipeline.YamlPath })
    }

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $key     = ($current.Repository + '/' + $current.Path).ToLowerInvariant()

        if (-not $visited.Add($key)) { continue }     # already walked: cycles and diamonds stop here

        $fromId = & $addYamlNode $current.Repository $current.Path

        if (-not $content.ContainsKey($key)) {
            $content[$key] = Get-AzDoPipelineYaml -Organisation $Organisation -Project $Project `
                                -Repository $current.Repository -Path $current.Path
        }
        $text = $content[$key]

        if ($null -eq $text) {
            Write-Warning ("Could not read '{0}' from repository '{1}'" -f $current.Path, $current.Repository)
            continue
        }

        $references = @(Get-AzDoPipelineReference -Content $text `
                            -SourceRepository $current.Repository -SourcePath $current.Path)

        # A file's aliases come from its own resources.repositories and are not
        # inherited by the files it includes: each document declares its own.
        $aliasMap = @{}
        foreach ($reference in $references) {
            if ($reference.Kind -ne 'repositoryResource') { continue }
            if (-not $reference.Alias) { continue }

            $aliasMap[$reference.Alias] = @{
                Repository = Get-AzDoShortRepositoryName -Name ([string]$reference.RepositoryName)
                Project    = Get-AzDoRepositoryProjectName -Name ([string]$reference.RepositoryName)
                Type       = [string]$reference.ResourceType
                Ref        = $reference.RepositoryRef
            }
        }

        foreach ($reference in $references) {
            $resolved = $reference | Resolve-AzDoPipelineReference `
                            -SourceRepository $current.Repository -SourcePath $current.Path `
                            -AliasMap $aliasMap -Repository $repos -Pipeline $pipelines `
                            -Inventory $inventory -Project $Project

            $alias = $null
            if ($reference.Kind -in @('repositoryResource', 'pipelineResource')) {
                $alias = $reference.Alias
            }
            elseif ($reference.Kind -in @('template', 'extends')) {
                $split = Split-AzDoTemplateReference -Reference ([string]$reference.Reference)
                $alias = $split.Alias
            }
            elseif ($reference.Kind -eq 'checkout' -and $reference.Reference -notin @('self', 'none')) {
                $alias = [string]$reference.Reference
            }

            if (-not $resolved.Resolved) {
                & $addEdge $fromId ('unresolved:' + $reference.Reference) 'unresolved' `
                           ([string]$reference.Reference) ([string]$reference.Kind) $alias $resolved.Reason
                continue
            }

            switch ($resolved.TargetKind) {
                'none' {
                    # 'checkout: none' is an instruction, not a dependency.
                    break
                }
                'repo' {
                    & $addEdge $fromId (& $repoNodeId $resolved.TargetRepository) ([string]$reference.Kind) `
                               ([string]$reference.Reference) $null $alias $null
                    break
                }
                'pipeline' {
                    & $addEdge $fromId (& $pipelineNodeId $resolved.TargetPipeline) ([string]$reference.Kind) `
                               ([string]$reference.Reference) $null $alias $null
                    break
                }
                'yaml' {
                    $toId = & $addYamlNode $resolved.TargetRepository $resolved.TargetPath
                    & $addEdge $fromId $toId ([string]$reference.Kind) `
                               ([string]$reference.Reference) $null $alias $null

                    $queue.Enqueue([pscustomobject]@{
                        Repository = $resolved.TargetRepository
                        Path       = $resolved.TargetPath
                    })
                    break
                }
            }
        }
    }

    # Deterministic order: the same project must produce byte-identical output
    # on two runs, so the result can be diffed and committed.
    $orderedNodes = @($nodes.Values | Sort-Object @{ Expression = { $_.kind } }, @{ Expression = { $_.id } })
    $orderedEdges = @($edges | Sort-Object @{ Expression = { $_.from } }, @{ Expression = { $_.kind } },
                                            @{ Expression = { if ($_.Contains('ref')) { $_.ref } else { '' } } },
                                            @{ Expression = { $_.to } })

    [pscustomobject]@{
        version      = 1
        organisation = $Organisation
        project      = $Project
        generatedBy  = 'Get-AzDoPipelineDependencyGraph'
        nodes        = @($orderedNodes | ForEach-Object { [pscustomobject]$_ })
        edges        = @($orderedEdges | ForEach-Object { [pscustomobject]$_ })
    }
}
