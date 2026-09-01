function Get-AzDoPipelineDependencyGraph {
    <#
    .SYNOPSIS
        The dependency graph of a project's pipelines, their YAML, and the repositories they reference.
    .DESCRIPTION
        Answers "if I change this template, which pipelines break?".

        Nodes are keyed by identity, never by traversal position. A template two
        pipelines include is ONE node with in-degree 2; building a tree per
        pipeline and concatenating inflates every metric computed from the graph
        in the direction that looks busiest.

        The node set is seeded from the definition list rather than from the edge
        list, so a pipeline that references nothing and that nothing references
        still appears. Its absence would look exactly like a correct answer.

        Repository nodes come only from resources.repositories and checkout. The
        repositories endpoint is used to look files up, never to emit nodes: a
        project has repositories no pipeline touches, and including them answers
        a different question.

        The walk is cycle-safe. Every edge is recorded BEFORE the visited check,
        so the edge that closes a cycle survives; dropping it leaves a
        clean-looking tree, which is a lie. Cycles found are reported as
        warnings.
    .PARAMETER Organisation
        The Azure DevOps organisation. An input, never discovered.
    .PARAMETER Project
        The project within the organisation.
    .PARAMETER Ref
        The branch to read every file at. Defaults to each repository's default branch.
    .EXAMPLE
        Get-AzDoPipelineDependencyGraph -Organisation jlbalmerjr1 -Project ClaudeTesting

        The whole graph, as data.
    .OUTPUTS
        PSAzureDevOpsGraph.Graph
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)] [ValidateNotNullOrEmpty()] [string] $Organisation,
        [Parameter(Mandatory, Position = 1)] [ValidateNotNullOrEmpty()] [string] $Project,
        [string] $Ref
    )

    process {
        $nodes = [ordered] @{}
        $edges = [System.Collections.Generic.List[object]]::new()
        $fileCache = @{}
        $visited = [System.Collections.Generic.HashSet[string]]::new()
        $backEdges = [System.Collections.Generic.List[string]]::new()
        $queue = [System.Collections.Generic.Queue[object]]::new()

        $reference = $Ref
        $organisation = $Organisation
        $project = $Project

        # Populates the cache and answers whether the file is there. One fetch
        # per unique file for the whole walk.
        $testFile = {
            param([string] $repositoryName, [string] $filePath)
            $key = "$repositoryName/$filePath"
            if (-not $fileCache.ContainsKey($key)) {
                $fileCache[$key] = Get-AzDoPipelineYaml -Organisation $organisation -Project $project `
                    -Repository $repositoryName -Path $filePath -Ref $reference
            }
            $null -ne $fileCache[$key]
        }.GetNewClosure()

        function Add-Node {
            param([System.Collections.IDictionary] $Node)
            if (-not $nodes.Contains($Node.id)) { $nodes[$Node.id] = $Node }
        }

        # --- Seed from the definition list, so orphans survive -----------------
        foreach ($definition in Get-AzDoPipeline -Organisation $Organisation -Project $Project) {
            $pipelineNode = [ordered] @{ id = "pipeline:$($definition.Name)"; kind = 'pipeline'; name = $definition.Name }
            if ($definition.RepositoryName) { $pipelineNode['repo'] = $definition.RepositoryName }
            Add-Node $pipelineNode

            if (-not $definition.RepositoryName) { continue }

            # The repository a definition lives in is part of the answer: it is
            # where the pipeline would have to be changed. A repository that
            # neither hosts a definition nor is referenced by one stays out -
            # that is still the rule, and it is what keeps an empty repository
            # nobody touches from appearing.
            Add-Node ([ordered] @{ id = "repo:$($definition.RepositoryName)"; kind = 'repo'; name = $definition.RepositoryName })

            if (-not $definition.YamlPath) { continue }

            $yamlId = "yaml:$($definition.RepositoryName)/$($definition.YamlPath)"
            $definitionNode = [ordered] @{
                id   = $yamlId
                kind = 'yaml'
                name = $definition.YamlPath
                repo = $definition.RepositoryName
                path = "repos/$($definition.RepositoryName)/$($definition.YamlPath)"
            }
            Add-Node $definitionNode
            $edges.Add([ordered] @{ from = "pipeline:$($definition.Name)"; to = $yamlId; kind = 'definition' })

            if ($visited.Add($yamlId)) {
                $queue.Enqueue(@{ Repository = $definition.RepositoryName; Path = $definition.YamlPath; Id = $yamlId })
            }
        }

        # --- Walk ---------------------------------------------------------------
        while ($queue.Count) {
            $file = $queue.Dequeue()

            $null = & $testFile $file.Repository $file.Path
            $text = $fileCache["$($file.Repository)/$($file.Path)"]
            if ($null -eq $text) {
                Write-Verbose "No such file: $($file.Repository)/$($file.Path)"
                continue
            }

            $references = @(Get-AzDoPipelineReference -Yaml $text)

            # The aliases are the ones THIS file declares. An alias declared by
            # the pipeline that started the traversal is not in scope here.
            $aliases = @{}
            foreach ($declaration in $references | Where-Object { $_.Kind -eq 'repositoryResource' -and $_.Alias }) {
                $aliases[$declaration.Alias] = $declaration.Repository
            }

            foreach ($item in $references) {
                $resolution = Resolve-AzDoPipelineReference -Reference $item `
                    -SourceRepository $file.Repository -SourcePath $file.Path `
                    -Alias $aliases -TestFile $testFile

                # Key order follows the schema so two runs, and two readers,
                # see the same file.
                $edge = [ordered] @{
                    from = $file.Id
                    to   = $resolution.TargetId
                    kind = $resolution.Resolved ? $item.Kind : 'unresolved'
                    ref  = $item.Reference
                }
                if (-not $resolution.Resolved) { $edge['refKind'] = $item.Kind }
                # alias only where it is information the ref does not already
                # carry. A template's @alias is inside its ref text and a
                # checkout's ref IS the alias; a resource declares one that
                # nothing else states.
                if ($item.Alias -and $item.Kind -in 'repositoryResource', 'pipelineResource') {
                    $edge['alias'] = $item.Alias
                }
                if (-not $resolution.Resolved) { $edge['reason'] = $resolution.Reason }

                # ALWAYS record the edge, then decline to descend.
                $edges.Add($edge)

                if (-not $resolution.Resolved) { continue }

                switch ($resolution.TargetKind) {
                    'repo' {
                        Add-Node ([ordered] @{ id = $resolution.TargetId; kind = 'repo'; name = $resolution.Repository })
                    }
                    'yaml' {
                        $targetNode = [ordered] @{
                            id   = $resolution.TargetId
                            kind = 'yaml'
                            name = $resolution.Path
                            repo = $resolution.Repository
                            path = "repos/$($resolution.Repository)/$($resolution.Path)"
                        }
                        Add-Node $targetNode
                        if ($visited.Add($resolution.TargetId)) {
                            $queue.Enqueue(@{ Repository = $resolution.Repository; Path = $resolution.Path; Id = $resolution.TargetId })
                        } else {
                            $backEdges.Add("$($file.Id) -> $($resolution.TargetId)")
                        }
                    }
                }
            }
        }

        if ($backEdges.Count) {
            Write-Warning "The graph contains $($backEdges.Count) edge(s) back to an already-visited file: $($backEdges -join '; ')"
        }

        # Sorted, so two runs of the same project diff to nothing.
        $sortedNodes = @($nodes.Values | Sort-Object -Property { $_.id } | ForEach-Object { [pscustomobject] $_ })
        $sortedEdges = @($edges |
                Sort-Object -Property { $_.from }, { $_.to }, { $_.kind }, { $_.ref } |
                ForEach-Object { [pscustomobject] $_ })

        [pscustomobject] @{
            PSTypeName   = 'PSAzureDevOpsGraph.Graph'
            version      = 1
            organisation = $Organisation
            project      = $Project
            generatedBy  = 'Get-AzDoPipelineDependencyGraph'
            nodes        = $sortedNodes
            edges        = $sortedEdges
        }
    }
}
