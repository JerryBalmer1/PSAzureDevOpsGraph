function Get-AzDoPipelineDependencyGraph {
    <#
    .SYNOPSIS
        The dependency graph of a project's pipelines, the YAML they reference,
        and the repositories those files live in.
    .DESCRIPTION
        Read-only. Walks every pipeline definition in the project, follows the
        references out of each YAML file, and returns nodes and edges in the
        shape of fixture/graph.schema.json.

        Three things it deliberately does:

        * Every repository in the project is a node, including empty ones and
          ones no pipeline touches. A project with an empty repository must not
          look identical to a project without one.
        * A reference that cannot be resolved becomes an edge of kind
          'unresolved' carrying a reason, never a dropped edge. A broken
          pipeline that vanishes from the output looks exactly like a clean one.
        * The walk is cycle-safe. A template cycle is a thing the fixture
          contains and a thing real projects contain; it is not an error here.
    .EXAMPLE
        Get-AzDoPipelineDependencyGraph -Organisation jlbalmerjr1 -Project ClaudeTesting
    #>
    [CmdletBinding()]
    [OutputType('PSAzureDevOpsGraph.DependencyGraph')]
    param(
        [Parameter(Mandatory)][string]$Organisation,
        [Parameter(Mandatory)][string]$Project,
        # Branch to read every file at. Defaults to each repository's default branch.
        [string]$Ref
    )

    $nodes = [ordered]@{}
    $edges = [System.Collections.Generic.List[object]]::new()

    $addNode = {
        param([string]$Id, [hashtable]$Properties)
        if ($nodes.Contains($Id)) { return }
        $node = [ordered]@{ id = $Id; kind = $Properties['kind']; name = $Properties['name'] }
        foreach ($key in 'repo', 'path') {
            if ($Properties.ContainsKey($key) -and $Properties[$key]) { $node[$key] = $Properties[$key] }
        }
        $nodes[$Id] = $node
    }
    $addEdge = {
        param([hashtable]$Edge)
        $e = [ordered]@{ from = $Edge['from']; to = $Edge['to']; kind = $Edge['kind'] }
        foreach ($key in 'ref', 'refKind', 'alias', 'reason') {
            if ($Edge.ContainsKey($key) -and $Edge[$key]) { $e[$key] = $Edge[$key] }
        }
        $edges.Add($e)
    }

    $repoId     = { param([string]$Name) "repo:$Name" }
    $pipelineId = { param([string]$Name) "pipeline:$Name" }
    $yamlId     = { param([string]$Repository, [string]$Path) "yaml:$Repository/$Path" }

    # --- repositories -------------------------------------------------------
    # The inventory decides what exists; it does not decide what is a node. A
    # repository earns a node by taking part in the graph -- by holding one of
    # the YAML files or by being the target of an edge. A repository that holds
    # no pipeline YAML and that nothing references is not a dependency of
    # anything, and adding it would put a node in the graph with no path to any
    # pipeline.
    $repositories = @(Get-AzDoRepository -Organisation $Organisation -Project $Project)
    $repositoryNames = @($repositories | ForEach-Object Name)
    $usedRepositories = [System.Collections.Generic.HashSet[string]]::new()

    # --- pipeline definitions ----------------------------------------------
    $pipelines = @(Get-AzDoPipeline -Organisation $Organisation -Project $Project)
    $pipelineNames = @($pipelines | ForEach-Object Name)

    # --- one fetch per file, however many references reach it ---------------
    $yamlCache = @{}
    $fetch = {
        param([string]$Repository, [string]$Path)
        $key = "$Repository/$Path"
        if (-not $yamlCache.ContainsKey($key)) {
            $arguments = @{
                Organisation = $Organisation; Project = $Project
                Repository   = $Repository;   Path    = $Path
            }
            if ($Ref) { $arguments['Ref'] = $Ref }
            $yamlCache[$key] = Get-AzDoPipelineYaml @arguments
        }
        $yamlCache[$key]
    }

    $queue   = [System.Collections.Generic.Queue[object]]::new()
    $visited = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($pipeline in ($pipelines | Sort-Object Name)) {
        & $addNode (& $pipelineId $pipeline.Name) @{
            kind = 'pipeline'; name = $pipeline.Name; repo = $pipeline.Repository
        }
        if (-not $pipeline.Path) { continue }

        $target = & $yamlId $pipeline.Repository $pipeline.Path
        & $addNode $target @{
            kind = 'yaml'; name = $pipeline.Path; repo = $pipeline.Repository
            path = "repos/$($pipeline.Repository)/$($pipeline.Path)"
        }
        $null = $usedRepositories.Add($pipeline.Repository)
        & $addEdge @{ from = (& $pipelineId $pipeline.Name); to = $target; kind = 'definition' }
        $queue.Enqueue([pscustomobject]@{ Repository = $pipeline.Repository; Path = $pipeline.Path })
    }

    # --- follow the references ----------------------------------------------
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $key = "$($current.Repository)/$($current.Path)"
        if (-not $visited.Add($key)) { continue }

        $document = & $fetch $current.Repository $current.Path
        if (-not $document -or -not $document.Found) { continue }

        $references = @(Get-AzDoPipelineReference -Yaml $document.Yaml `
                -SourceRepository $current.Repository -SourcePath $current.Path)

        # Aliases are declared per file and do not cross files.
        $aliases = @{}
        foreach ($reference in ($references | Where-Object Kind -eq 'repositoryResource')) {
            if ($reference.Alias) {
                $name = $reference.Name
                $aliases[$reference.Alias] = if ($name -match '/') { ($name -split '/')[-1] } else { $name }
            }
        }

        $from = & $yamlId $current.Repository $current.Path

        foreach ($reference in $references) {
            $result = Resolve-AzDoPipelineReference -Reference $reference `
                -SourceRepository $current.Repository -SourcePath $current.Path `
                -Alias $aliases -KnownRepository $repositoryNames -KnownPipeline $pipelineNames
            if (-not $result) { continue }

            $refText = $reference.Reference

            # 'alias' records where an alias is DECLARED -- the 'repository:' key
            # of a repository resource and the 'pipeline:' key of a pipeline
            # resource. It is not recorded on edges that merely USE an alias: the
            # use is already visible in 'ref', and repeating it there states the
            # same fact once per use.
            $aliasAttribute = if ($reference.Kind -in 'repositoryResource', 'pipelineResource') { $reference.Alias } else { $null }

            if (-not $result.Resolved) {
                # The target keeps the shape it would have had. An unresolved
                # reference names a file that should exist somewhere; recording
                # that place is what makes the edge actionable.
                & $addEdge @{
                    from = $from; to = (& $yamlId $result.Repository $result.Path); kind = 'unresolved'
                    ref = $refText; refKind = $reference.Kind; alias = $aliasAttribute
                    reason = $result.Reason
                }
                continue
            }

            switch ($result.TargetKind) {
                'repo' {
                    # 'checkout: self' is the repository the file is already in.
                    # It is a build instruction, not a dependency on anything the
                    # file would not otherwise have.
                    if ($reference.Kind -eq 'checkout' -and $refText -eq 'self') { continue }
                    $null = $usedRepositories.Add($result.Repository)
                    & $addEdge @{
                        from = $from; to = (& $repoId $result.Repository); kind = $reference.Kind
                        ref = $refText; alias = $aliasAttribute
                    }
                }
                'pipeline' {
                    & $addEdge @{
                        from = $from; to = (& $pipelineId $result.Pipeline); kind = $reference.Kind
                        ref = $refText; alias = $aliasAttribute
                    }
                }
                'yaml' {
                    $document2 = & $fetch $result.Repository $result.Path
                    if (-not $document2 -or -not $document2.Found) {
                        & $addEdge @{
                            from = $from; to = (& $yamlId $result.Repository $result.Path); kind = 'unresolved'
                            ref = $refText; refKind = $reference.Kind; alias = $aliasAttribute
                            reason = "file-not-found: resolved to $($result.Path) in $($result.Repository), which does not exist"
                        }
                        continue
                    }
                    $to = & $yamlId $result.Repository $result.Path
                    & $addNode $to @{
                        kind = 'yaml'; name = $result.Path; repo = $result.Repository
                        path = "repos/$($result.Repository)/$($result.Path)"
                    }
                    $null = $usedRepositories.Add($result.Repository)
                    & $addEdge @{
                        from = $from; to = $to; kind = $reference.Kind
                        ref = $refText; alias = $aliasAttribute
                    }
                    $queue.Enqueue([pscustomobject]@{ Repository = $result.Repository; Path = $result.Path })
                }
            }
        }
    }

    # Repositories that took part, and only those. See the note above.
    foreach ($name in ($usedRepositories | Sort-Object)) {
        & $addNode (& $repoId $name) @{ kind = 'repo'; name = $name }
    }

    $orderedNodes = @($nodes.Values | Sort-Object { $_.id })
    $orderedEdges = @($edges | Sort-Object { $_.from }, { $_.to }, { $_.kind })

    [pscustomobject]@{
        PSTypeName   = 'PSAzureDevOpsGraph.DependencyGraph'
        version      = 1
        organisation = $Organisation
        project      = $Project
        generatedBy  = 'Get-AzDoPipelineDependencyGraph'
        nodes        = $orderedNodes
        edges        = $orderedEdges
    }
}
