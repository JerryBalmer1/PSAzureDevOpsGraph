function Get-AzDoPipelineDependencyGraph {
    <#
    .SYNOPSIS
        The dependency graph of a project's pipelines, as nodes and edges.
    .DESCRIPTION
        Answers "if I change this template, which pipelines break?".

        Three properties of the assembly are load-bearing and each has a failure
        mode that looks like a correct answer:

        NODE IDENTITY IS THE THING, NEVER ITS POSITION. Nodes live in a
        dictionary keyed by id, so a template two pipelines include is ONE node
        with in-degree 2. Building a tree per pipeline and concatenating inflates
        every count derived from the graph, in the direction that looks busiest.

        THE NODE SET IS SEEDED FROM THE DEFINITION LIST, so orphans survive. A
        pipeline that references nothing and that nothing references is exactly
        the one a reader wants to find, and deriving nodes from edges makes it
        cease to exist -- an absence that looks just like a correct answer.

        A REPOSITORY NOTHING REFERENCES IS NOT A NODE. Repository nodes come from
        resources.repositories and checkout, never from the repositories
        endpoint, which is used only to look files up. Emitting a node per
        repository answers "what is in this project" instead.

        The walk is cycle-safe by recording every edge BEFORE the visited check
        and declining only to descend. Dropping the edge that closes a cycle
        produces a clean-looking tree, which is a lie; the cycles found are
        reported rather than terminated silently.
    .PARAMETER Organisation
        The Azure DevOps organisation. An input, never discovered -- the accounts
        API needs a scope a Code+Build read token does not have.
    .PARAMETER Project
        The project name.
    .EXAMPLE
        # Needs $env:AZDO_PAT with Code (Read) and Build (Read).
        Get-AzDoPipelineDependencyGraph -Organisation jlbalmerjr1 -Project ClaudeTesting

        The whole graph, ready for Export-AzDoPipelineDependencyGraph.
    .OUTPUTS
        PSAzureDevOpsGraph.Graph
    #>
    [CmdletBinding()]
    [OutputType('PSAzureDevOpsGraph.Graph')]
    param(
        [Parameter(Mandatory, Position = 0)] [ValidateNotNullOrEmpty()] [string] $Organisation,
        [Parameter(Mandatory, Position = 1)] [ValidateNotNullOrEmpty()] [string] $Project
    )

    process {
        # Repositories are looked up, never emitted. This is the list that makes
        # file resolution possible; it is not the node set.
        $repositories = @(Get-AzDoRepository -Organisation $Organisation -Project $Project)
        $repositoryByName = @{}
        foreach ($repository in $repositories) { $repositoryByName[$repository.Name] = $repository }

        # Existence, gathered once. One listing per repository beats a 404 probe
        # per reference, and it lets resolution report file-not-found as a fact
        # it holds rather than an exception it caught.
        $knownPath = [System.Collections.Generic.List[string]]::new()
        foreach ($repository in $repositories) {
            foreach ($file in Get-AzDoRepositoryFile -Organisation $Organisation -Project $Project -RepositoryId $repository.Id) {
                $knownPath.Add("$($repository.Name)/$file")
            }
        }
        Write-Verbose "$($knownPath.Count) file(s) across $($repositories.Count) repositories."

        $nodes = @{}
        $edges = [System.Collections.Generic.List[object]]::new()
        $visited = [System.Collections.Generic.HashSet[string]]::new()

        $queue = [System.Collections.Generic.Queue[object]]::new()

        $addNode = {
            param($Id, $Kind, $Name, $Repo, $Path)
            if ($nodes.ContainsKey($Id)) { return }
            $node = [ordered]@{ id = $Id; kind = $Kind; name = $Name }
            # A pipeline node carries the repository its definition lives in, and
            # a yaml node carries its repository and path. path is the yaml
            # node's alone -- the schema says so -- but repo is a positive fact
            # about a definition too, and a repo node's own name already states
            # it.
            if ($Kind -in @('yaml', 'pipeline')) { $node['repo'] = $Repo }
            if ($Kind -eq 'yaml') { $node['path'] = $Path }
            $nodes[$Id] = $node
        }

        # Seed from the definition list, so a pipeline with no references at all
        # still appears.
        $pipelines = @(Get-AzDoPipeline -Organisation $Organisation -Project $Project)
        foreach ($pipeline in $pipelines) {
            $pipelineId = "pipeline:$($pipeline.Name)"
            & $addNode $pipelineId 'pipeline' $pipeline.Name $pipeline.RepositoryName $null

            # A repository that HOSTS a definition is part of the answer, the
            # same way one referenced by resources.repositories or checkout is:
            # changing it can break the pipelines defined in it. What is still
            # excluded is a repository that does neither -- the project's own
            # empty repository is in the project, visible to any call that lists
            # repositories, and must not appear.
            if ($pipeline.RepositoryName) {
                & $addNode "repo:$($pipeline.RepositoryName)" 'repo' $pipeline.RepositoryName $null $null
            }

            if (-not $pipeline.YamlPath) {
                Write-Verbose "Definition '$($pipeline.Name)' has no YAML process; no definition edge."
                continue
            }

            $yamlId = "yaml:$($pipeline.RepositoryName)/$($pipeline.YamlPath)"
            & $addNode $yamlId 'yaml' $pipeline.YamlPath $pipeline.RepositoryName "repos/$($pipeline.RepositoryName)/$($pipeline.YamlPath)"

            # A definition edge is a claim about the Azure DevOps project rather
            # than about a file, so it carries no ref.
            $edges.Add([ordered]@{ from = $pipelineId; to = $yamlId; kind = 'definition' })

            if ($visited.Add($yamlId)) {
                $queue.Enqueue([pscustomobject]@{ Id = $yamlId; Repository = $pipeline.RepositoryName; Path = $pipeline.YamlPath })
            }
        }

        while ($queue.Count) {
            $file = $queue.Dequeue()

            $repository = $repositoryByName[$file.Repository]
            if ($null -eq $repository) {
                Write-Verbose "No repository '$($file.Repository)' in the project; cannot read $($file.Path)."
                continue
            }

            $text = Get-AzDoItemContent -Organisation $Organisation -Project $Project -RepositoryId $repository.Id -Path $file.Path
            if ($null -eq $text) { continue }

            $document = ConvertFrom-AzDoYamlText -Text $text
            if ($null -eq $document) { continue }

            $references = @(Read-AzDoYamlReference -Node $document)

            # The aliases belong to THIS file. Anything not declared here is
            # undeclared, whatever other files in the repository declare.
            $aliases = @{}
            foreach ($reference in $references) {
                if ($reference.RefKind -eq 'repositoryResource' -and $reference.Alias) {
                    $aliases[$reference.Alias] = $reference.Target
                }
            }

            foreach ($reference in $references) {
                $resolution = Resolve-AzDoPipelineReference -Reference $reference `
                    -SourceRepository $file.Repository -SourcePath $file.Path `
                    -Alias $aliases -KnownPath $knownPath

                # alias is written where the reference DECLARES one, and not
                # where it merely uses one. On a resource entry the alias is the
                # fact being stated. On a template, extends or checkout
                # reference the alias is already inside ref -- as the @suffix,
                # or as the whole of it -- so writing it again restates rather
                # than adds, and in this contract an absent optional field means
                # NOT STATED rather than false.
                $declaresAlias = $reference.RefKind -in @('repositoryResource', 'pipelineResource')

                $edge = [ordered]@{ from = $file.Id; to = $null; kind = $null; ref = $reference.Ref }

                if (-not $resolution.Resolved) {
                    # An unresolved target must not collide with a real node. For
                    # an undeclared alias the repository is unknown and is NOT
                    # guessed -- the alias stays in the id.
                    $edge['to'] = switch ($reference.RefKind) {
                        'checkout' { "repo:@$($reference.Alias)" }
                        'pipelineResource' { "pipeline:@$($reference.Alias)" }
                        default {
                            # Branches on ReasonCode, never on Reason. Reason is
                            # a sentence written for a person; a decision taken
                            # on its text breaks silently the moment the wording
                            # improves, and produces an id like "yaml:/".
                            if ($resolution.ReasonCode -eq 'alias-not-declared') { "yaml:@$($reference.Alias)/$($reference.Path)" }
                            else { "yaml:$($resolution.Repository)/$($resolution.Path)" }
                        }
                    }
                    $edge['kind'] = 'unresolved'
                    $edge['refKind'] = $reference.RefKind
                    if ($declaresAlias) { $edge['alias'] = $reference.Alias }
                    $edge['reason'] = $resolution.Reason
                    $edges.Add($edge)
                    continue
                }

                switch ($resolution.TargetKind) {
                    'repo' {
                        $targetId = "repo:$($resolution.Repository)"
                        & $addNode $targetId 'repo' $resolution.Repository $null $null
                        $edge['to'] = $targetId
                        $edge['kind'] = $reference.RefKind
                        if ($declaresAlias) { $edge['alias'] = $reference.Alias }
                        $edges.Add($edge)
                    }
                    'pipeline' {
                        $targetId = "pipeline:$($resolution.Name)"
                        $edge['to'] = $targetId
                        if ($nodes.ContainsKey($targetId)) {
                            $edge['kind'] = $reference.RefKind
                            if ($declaresAlias) { $edge['alias'] = $reference.Alias }
                        } else {
                            $edge['kind'] = 'unresolved'
                            $edge['refKind'] = $reference.RefKind
                            if ($declaresAlias) { $edge['alias'] = $reference.Alias }
                            $edge['reason'] = 'file-not-found'
                        }
                        $edges.Add($edge)
                    }
                    default {
                        $targetId = "yaml:$($resolution.Repository)/$($resolution.Path)"
                        & $addNode $targetId 'yaml' $resolution.Path $resolution.Repository "repos/$($resolution.Repository)/$($resolution.Path)"
                        $edge['to'] = $targetId
                        $edge['kind'] = $reference.RefKind
                        if ($declaresAlias) { $edge['alias'] = $reference.Alias }

                        # ALWAYS record the edge, then decline to descend.
                        $edges.Add($edge)

                        if ($visited.Add($targetId)) {
                            $queue.Enqueue([pscustomobject]@{ Id = $targetId; Repository = $resolution.Repository; Path = $resolution.Path })
                        }
                    }
                }
            }
        }

        # A cycle that terminates silently is indistinguishable from no cycle, so
        # the cycles are reported. They are found from the ASSEMBLED EDGES rather
        # than from arrivals during the walk: an arrival at an already-visited
        # node is usually a diamond, and calling that a cycle is the same defect
        # as reporting none, in the other direction. Both edges of a real cycle
        # are in the graph -- the traversal declined to descend, it did not drop
        # the edge that closes it.
        $cycles = @(Find-AzDoGraphCycle -Edge @($edges))
        if ($cycles.Count) {
            Write-Warning "Dependency cycle(s) found: $($cycles -join '; ')"
        }

        # Sorted, so two runs of the same project diff to nothing. A comparator
        # should be order-insensitive, but a graph that reorders between runs
        # cannot be diffed by eye or by git, which is half of what export is for.
        $orderedNodes = $nodes.Values | Sort-Object -Property { $_.id }
        $orderedEdges = $edges | Sort-Object -Property { $_.from }, { $_.to }, { $_.kind }, { [string] $_.ref }

        $sortedNodes = @($orderedNodes | ForEach-Object { [pscustomobject] $_ })
        $sortedEdges = @($orderedEdges | ForEach-Object { [pscustomobject] $_ })

        [pscustomobject]@{
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
