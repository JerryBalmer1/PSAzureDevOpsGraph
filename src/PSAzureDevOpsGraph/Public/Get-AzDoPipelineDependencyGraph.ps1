function Get-AzDoPipelineDependencyGraph {
    <#
    .SYNOPSIS
        The dependency graph of a project's pipelines, as nodes and edges.
    .DESCRIPTION
        Answers the question nobody can answer by reading a repository: if I
        change this template, which pipelines break?

        The node set is seeded from the DEFINITION LIST, not from the edges. A
        pipeline that references nothing and that nothing references is still a
        node, joined to its YAML by one definition edge. Building the node set
        from the edge list makes anything with no edges cease to exist, and that
        is the one pipeline a reader might most want to find - its absence looks
        exactly like a correct answer.

        Repository nodes come only from resources.repositories and checkout,
        never from the repositories endpoint. That endpoint is used to look
        files up. A graph that emits a node per repository in the project
        answers "what is in this project" instead.

        The traversal records every edge BEFORE the visited check, then declines
        to descend. Adding a visited set and dropping the edge that closes a
        cycle produces a clean-looking tree, which is a lie; back edges are
        reported on the verbose stream and are present in the output.
    .PARAMETER Organisation
        The Azure DevOps organisation. Not discovered - the accounts and profile
        APIs need a scope a Code+Build read token does not have.
    .PARAMETER Project
        The project to graph. Every route this module calls is project-scoped.
    .PARAMETER Ref
        The branch or ref to read every file at. Defaults to each repository's
        default branch.
    .EXAMPLE
        # Needs $env:AZDO_PAT with Code (Read) and Build (Read).
        Get-AzDoPipelineDependencyGraph -Organisation jlbalmerjr1 -Project ClaudeTesting

        Produces the graph for the project, including unresolved references.
    .EXAMPLE
        # Needs $env:AZDO_PAT with Code (Read) and Build (Read).
        $g = Get-AzDoPipelineDependencyGraph -Organisation jlbalmerjr1 -Project ClaudeTesting
        $g.edges | Where-Object kind -eq 'unresolved'

        The broken references, which are the answer the tool exists to give.
    .OUTPUTS
        PSAzureDevOpsGraph.Graph
    #>
    [CmdletBinding()]
    [OutputType('PSAzureDevOpsGraph.Graph')]
    param(
        [Parameter(Mandatory, Position = 0)] [ValidateNotNullOrEmpty()] [string] $Organisation,
        [Parameter(Mandatory, Position = 1)] [ValidateNotNullOrEmpty()] [string] $Project,
        [string] $Ref
    )

    $repositories = @(Get-AzDoRepository -Organisation $Organisation -Project $Project)
    $definitions = @(Get-AzDoPipeline -Organisation $Organisation -Project $Project)

    $knownRepository = @($repositories | ForEach-Object { $_.Name })
    $knownPipeline = @($definitions | ForEach-Object { $_.Name })

    # NOT .GetNewClosure(). A closure is rebound to a fresh dynamic module, and
    # module-private functions - Get-AzDoCachedYaml among them - are then not
    # visible from it at all. Left as a plain scriptblock it keeps this module's
    # session state, and PowerShell's dynamic scoping resolves $graphCache and
    # the three context variables from this function's scope when the predicate
    # is invoked further down the call stack.
    $graphCache = @{}
    $graphOrganisation = $Organisation
    $graphProject = $Project
    $graphRef = $Ref
    $testFile = {
        param($Repository, $Path)
        $null -ne (Get-AzDoCachedYaml -Cache $graphCache -Organisation $graphOrganisation `
                -Project $graphProject -Repository $Repository -Path $Path -Ref $graphRef)
    }

    $nodes = [ordered]@{}
    $edges = [ordered]@{}
    $queue = [System.Collections.Generic.Queue[object]]::new()
    $visited = [System.Collections.Generic.HashSet[string]]::new()
    $backEdge = [System.Collections.Generic.List[string]]::new()

    foreach ($definition in $definitions) {
        $pipelineId = "pipeline:$($definition.Name)"
        Add-AzDoGraphNode -Node $nodes -Id $pipelineId -Kind 'pipeline' -Name $definition.Name

        if (-not $definition.YamlPath -or -not $definition.Repository) {
            Write-Verbose "Definition '$($definition.Name)' has no YAML file; it stays as an orphan node."
            continue
        }

        $yamlId = "yaml:$($definition.Repository)/$($definition.YamlPath)"
        Add-AzDoGraphNode -Node $nodes -Id $yamlId -Kind 'yaml' -Name $definition.YamlPath `
            -Repository $definition.Repository -Path "repos/$($definition.Repository)/$($definition.YamlPath)"

        # A definition edge carries no ref: it is a claim about the Azure DevOps
        # project rather than about a file.
        Add-AzDoGraphEdge -Edge $edges -From $pipelineId -To $yamlId -Kind 'definition'

        if ($visited.Add($yamlId)) {
            $queue.Enqueue([pscustomobject]@{
                    Id         = $yamlId
                    Repository = $definition.Repository
                    Path       = $definition.YamlPath
                })
        }
    }

    while ($queue.Count) {
        $file = $queue.Dequeue()

        # The same cache the existence predicate uses, so a file asked about
        # during resolution is not fetched a second time to read it.
        $content = Get-AzDoCachedYaml -Cache $graphCache -Organisation $graphOrganisation `
            -Project $graphProject -Repository $file.Repository -Path $file.Path -Ref $graphRef
        if ($null -eq $content) {
            Write-Verbose "No content for $($file.Id); it stays a node with no outgoing edges."
            continue
        }

        $references = @(Get-AzDoPipelineReference -Content $content)

        # The alias table belongs to THIS file. Carrying one table for the whole
        # traversal resolves a relative reference inside a cross-repository
        # template back into the repository the pipeline started in.
        $alias = @{}
        foreach ($reference in $references) {
            if ($reference.Kind -ne 'repositoryResource' -or -not $reference.Alias) { continue }
            $name = [string] $reference.Name
            $slashAt = $name.LastIndexOf('/')
            if ($slashAt -ge 0) { $name = $name.Substring($slashAt + 1) }
            $alias[$reference.Alias] = $name
        }

        foreach ($reference in $references) {
            $resolution = Resolve-AzDoPipelineReference -Reference $reference `
                -SourceRepository $file.Repository -SourcePath $file.Path `
                -Alias $alias -TestFile $testFile `
                -KnownRepository $knownRepository -KnownPipeline $knownPipeline

            if (-not $resolution.Resolved) {
                Add-AzDoGraphEdge -Edge $edges -From $file.Id -To $resolution.TargetId -Kind 'unresolved' `
                    -Reference $reference.Reference -ReferenceKind $reference.Kind `
                    -Alias $reference.Alias -Reason $resolution.Reason
                continue
            }

            switch ($resolution.TargetKind) {
                'yaml' {
                    Add-AzDoGraphNode -Node $nodes -Id $resolution.TargetId -Kind 'yaml' `
                        -Name $resolution.Path -Repository $resolution.Repository `
                        -Path "repos/$($resolution.Repository)/$($resolution.Path)"
                }
                'repo' {
                    Add-AzDoGraphNode -Node $nodes -Id $resolution.TargetId -Kind 'repo' -Name $resolution.Repository
                }
            }

            # ALWAYS record the edge, then decide whether to descend.
            Add-AzDoGraphEdge -Edge $edges -From $file.Id -To $resolution.TargetId -Kind $reference.Kind `
                -Reference $reference.Reference -Alias $reference.Alias

            if ($resolution.TargetKind -ne 'yaml') { continue }

            if ($visited.Add($resolution.TargetId)) {
                $queue.Enqueue([pscustomobject]@{
                        Id         = $resolution.TargetId
                        Repository = $resolution.Repository
                        Path       = $resolution.Path
                    })
            } else {
                $backEdge.Add("$($file.Id) -> $($resolution.TargetId)")
                Write-Verbose "Already visited $($resolution.TargetId); edge recorded, not descended."
            }
        }
    }

    if ($backEdge.Count) {
        # A cycle that terminates silently is indistinguishable from no cycle.
        Write-Verbose "Back edges (the traversal did not descend through these): $($backEdge -join '; ')"
    }

    # Sorted, because a graph that changes order between two runs cannot be
    # diffed by eye or by git, which is half of what the export is for.
    $sortedNodes = @($nodes.Values | Sort-Object -Property id)
    $sortedEdges = @($edges.Values | Sort-Object -Property from, to, kind, ref)

    # [ordered] so the six contract keys serialise in the order the schema
    # lists them, rather than in whatever order a hashtable happens to hash to.
    [pscustomobject][ordered]@{
        PSTypeName   = 'PSAzureDevOpsGraph.Graph'
        version      = 1
        organisation = $Organisation
        project      = $Project
        generatedBy  = 'Get-AzDoPipelineDependencyGraph'
        nodes        = $sortedNodes
        edges        = $sortedEdges
    }
}
