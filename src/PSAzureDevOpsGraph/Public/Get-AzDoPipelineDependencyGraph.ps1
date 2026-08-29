function Get-AzDoPipelineDependencyGraph {
    <#
        .SYNOPSIS
            Builds the dependency graph of a project's pipelines, the YAML they
            reference, and the repositories those files live in.

        .DESCRIPTION
            Answers the question no single file can: if I change this template,
            which pipelines break?

            Node identity is the thing, never its position in a traversal. Nodes
            live in a dictionary keyed by id, so a template two pipelines
            include is one node with in-degree two rather than two nodes.

            The node set is seeded from the DEFINITION LIST, not from the edge
            list, so a pipeline that references nothing and that nothing
            references still appears. Building nodes from edges makes an orphan
            cease to exist, and that is the one pipeline a reader might most
            want to find.

            Repository nodes come from the files and references in the graph,
            never from the repositories endpoint. A project has repositories no
            pipeline touches; including them answers "what is in this project"
            rather than "what do these pipelines depend on".

            The traversal records every edge BEFORE testing whether it has
            already visited the target, so a cycle produces both of its edges
            and still terminates.

        .PARAMETER Organisation
            The Azure DevOps organisation name.

        .PARAMETER Project
            The project name.

        .EXAMPLE
            Get-AzDoPipelineDependencyGraph -Organisation contoso -Project ClaudeTesting

            Returns the graph as an object with nodes and edges.

        .EXAMPLE
            Get-AzDoPipelineDependencyGraph -Organisation contoso -Project ClaudeTesting |
                Export-AzDoPipelineDependencyGraph -Path ./graph.json

            Builds the graph and writes it as JSON.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Organisation,
        [Parameter(Mandatory)] [string] $Project
    )

    $nodes = [ordered]@{}
    $edges = [System.Collections.Generic.List[object]]::new()
    $content = @{}

    $repositoryId = @{}
    foreach ($repo in (Get-AzDoRepository -Organisation $Organisation -Project $Project)) {
        $repositoryId[$repo.Name] = $repo.Id
    }

    $queue = [System.Collections.Generic.Queue[object]]::new()
    $visited = [System.Collections.Generic.HashSet[string]]::new()

    # Seed from the definitions. An orphan is a node because of this loop.
    foreach ($pipeline in (Get-AzDoPipeline -Organisation $Organisation -Project $Project)) {
        $pipelineId = "pipeline:$($pipeline.Name)"
        if (-not $nodes.Contains($pipelineId)) {
            $nodes[$pipelineId] = @{
                id = $pipelineId; kind = 'pipeline'; name = $pipeline.Name
                repo = $pipeline.RepositoryName
            }
        }

        if ([string]::IsNullOrWhiteSpace($pipeline.Path)) { continue }

        $path = Resolve-AzDoRepositoryPath -Path $pipeline.Path
        $yamlId = "yaml:$($pipeline.RepositoryName)/$path"
        if (-not $nodes.Contains($yamlId)) {
            $nodes[$yamlId] = @{
                id   = $yamlId; kind = 'yaml'; name = $path
                repo = $pipeline.RepositoryName
                path = "repos/$($pipeline.RepositoryName)/$path"
            }
        }

        $edges.Add(@{ from = $pipelineId; to = $yamlId; kind = 'definition' })

        if ($visited.Add($yamlId)) {
            $queue.Enqueue([pscustomobject]@{
                    Repository = $pipeline.RepositoryName; Path = $path; Id = $yamlId
                })
        }
    }

    while ($queue.Count -gt 0) {
        $file = $queue.Dequeue()

        $cacheKey = "$($file.Repository)/$($file.Path)"
        if (-not $content.ContainsKey($cacheKey)) {
            $lookupId = if ($repositoryId.ContainsKey($file.Repository)) {
                $repositoryId[$file.Repository]
            }
            else { $file.Repository }
            $content[$cacheKey] = Get-AzDoPipelineYaml -Organisation $Organisation -Project $Project `
                -RepositoryId $lookupId -Path $file.Path
        }
        $text = $content[$cacheKey]
        if ($null -eq $text) { continue }

        $references = @(Get-AzDoPipelineReference -Yaml $text -Path $file.Path)

        $aliasMap = @{}
        foreach ($reference in $references) {
            if ($reference.RefKind -eq 'repositoryResource' -and $reference.Alias) {
                $aliasMap[$reference.Alias] = $reference.Target
            }
        }

        foreach ($reference in $references) {

            if ($reference.RefKind -eq 'repositoryResource') {
                $target = "repo:$($reference.Target)"
                if (-not $nodes.Contains($target)) {
                    $nodes[$target] = @{ id = $target; kind = 'repo'; name = $reference.Target }
                }
                $edges.Add(@{
                        from  = $file.Id; to = $target; kind = 'repositoryResource'
                        ref   = $reference.Ref; alias = $reference.Alias
                    })
            }

            elseif ($reference.RefKind -eq 'pipelineResource') {
                $target = "pipeline:$($reference.Target)"
                if (-not $nodes.Contains($target)) {
                    $nodes[$target] = @{ id = $target; kind = 'pipeline'; name = $reference.Target }
                }
                $edges.Add(@{
                        from  = $file.Id; to = $target; kind = 'pipelineResource'
                        ref   = $reference.Ref; alias = $reference.Alias
                    })
            }

            elseif ($reference.RefKind -eq 'checkout') {
                # A checkout of an alias is a dependency on that repository -
                # never a template reference, and no template edge may be
                # invented from it.
                if ($aliasMap.ContainsKey($reference.Alias)) {
                    $repoName = $aliasMap[$reference.Alias]
                    $target = "repo:$repoName"
                    if (-not $nodes.Contains($target)) {
                        $nodes[$target] = @{ id = $target; kind = 'repo'; name = $repoName }
                    }
                    $edges.Add(@{
                            from = $file.Id; to = $target; kind = 'checkout'
                            ref  = $reference.Ref
                        })
                }
            }

            else {
                $resolution = Resolve-AzDoPipelineReference -Reference $reference `
                    -FromRepository $file.Repository -FromPath $file.Path -Alias $aliasMap

                if (-not $resolution.Resolved) {
                    # Keep the alias in the id so an unresolved target can never
                    # collide with a real node.
                    $edges.Add(@{
                            from    = $file.Id
                            to      = "yaml:@$($reference.Alias)/$($reference.Path)"
                            kind    = 'unresolved'; ref = $reference.Ref
                            refKind = $reference.RefKind
                            reason  = ('{0}: {1}' -f $resolution.Reason, $resolution.Detail)
                        })
                }
                else {
                    $targetId = "yaml:$($resolution.Repository)/$($resolution.Path)"

                    $targetKey = "$($resolution.Repository)/$($resolution.Path)"
                    if (-not $content.ContainsKey($targetKey)) {
                        $lookupId = if ($repositoryId.ContainsKey($resolution.Repository)) {
                            $repositoryId[$resolution.Repository]
                        }
                        else { $resolution.Repository }
                        $content[$targetKey] = Get-AzDoPipelineYaml -Organisation $Organisation `
                            -Project $Project -RepositoryId $lookupId -Path $resolution.Path
                    }

                    if ($null -eq $content[$targetKey]) {
                        $missingReason = 'file-not-found: resolved to {0} in {1}, which does not exist' -f $resolution.Path, $resolution.Repository
                        $edges.Add(@{
                                from    = $file.Id; to = $targetId; kind = 'unresolved'
                                ref     = $reference.Ref; refKind = $reference.RefKind
                                reason  = $missingReason
                            })
                    }
                    else {
                        if (-not $nodes.Contains($targetId)) {
                            $nodes[$targetId] = @{
                                id   = $targetId; kind = 'yaml'; name = $resolution.Path
                                repo = $resolution.Repository
                                path = "repos/$($resolution.Repository)/$($resolution.Path)"
                            }
                        }

                        # Recorded before the visited test, so the edge that
                        # closes a cycle is present and the walk still ends.
                        $edges.Add(@{
                                from = $file.Id; to = $targetId; kind = $reference.RefKind
                                ref  = $reference.Ref
                            })

                        if ($visited.Add($targetId)) {
                            $queue.Enqueue([pscustomobject]@{
                                    Repository = $resolution.Repository
                                    Path       = $resolution.Path
                                    Id         = $targetId
                                })
                        }
                    }
                }
            }
        }
    }

    # A repository holding a file in the graph is part of the answer. One that
    # merely exists in the project is not.
    foreach ($node in @($nodes.Values)) {
        if ($node.kind -ne 'yaml') { continue }
        $repoNodeId = "repo:$($node.repo)"
        if (-not $nodes.Contains($repoNodeId)) {
            $nodes[$repoNodeId] = @{ id = $repoNodeId; kind = 'repo'; name = $node.repo }
        }
    }

    # Real cycles, found by depth-first colouring over the finished edge set. A
    # breadth-first "have I seen this target" test cannot tell a cycle from a
    # diamond, and would report every shared template as one.
    $cycle = Get-AzDoGraphCycle -Edge @($edges)
    if ($cycle.Count -gt 0) {
        Write-Verbose "Cycles found: $($cycle -join '; ')"
    }

    [pscustomobject]@{
        version      = 1
        organisation = $Organisation
        project      = $Project
        generatedBy  = 'Get-AzDoPipelineDependencyGraph'
        nodes        = @($nodes.Values | Sort-Object -Property { $_.id })
        edges        = @($edges | Sort-Object -Property { $_.from }, { $_.to }, { $_.kind }, { $_.ref })
        BackEdge     = @($cycle)
    }
}
