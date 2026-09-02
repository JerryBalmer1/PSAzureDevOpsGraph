#Requires -Version 7.2

BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    $script:Module = Import-ModuleUnderTest
    $script:Where = Get-FixtureCoordinate
    $script:HasPat = [bool] $env:AZDO_PAT

    if (-not $script:HasPat) {
        # Announced, never quietly skipped. A layer that reports success where
        # nothing could contradict it is worse than one that says it did not run.
        Write-Warning 'AZDO_PAT is not set: the integration layer grades less than it claims to.'
    }

    if ($script:HasPat) {
        $script:Graph = Get-AzDoPipelineDependencyGraph -Organisation $script:Where.Organisation -Project $script:Where.Project -WarningAction SilentlyContinue
    }
}

Describe 'Against the live fixture' -Tag 'Integration', 'RequiresPat' -Skip:(-not $env:AZDO_PAT) {

    It 'lists the project repositories' {
        $repositories = @(Get-AzDoRepository -Organisation $script:Where.Organisation -Project $script:Where.Project)
        $repositories.Count | Should-BeGreaterThan 0
    }

    It 'finds a repository by name' {
        $one = @(Get-AzDoRepository -Organisation $script:Where.Organisation -Project $script:Where.Project -Name 'pipelines-main')
        $one.Count | Should-Be 1
    }

    It 'lists definitions carrying the repository and path their YAML lives at' {
        $pipelines = @(Get-AzDoPipeline -Organisation $script:Where.Organisation -Project $script:Where.Project)
        $pipelines.Count | Should-BeGreaterThan 0
        @($pipelines | Where-Object { $_.YamlPath }).Count | Should-BeGreaterThan 0
    }

    It 'reads one YAML document by repository and path' {
        $text = Get-AzDoPipelineYaml -Organisation $script:Where.Organisation -Project $script:Where.Project -RepositoryName 'pipelines-main' -Path 'pipelines/p01.yml'
        $text | Should-NotBeNull
    }

    It 'returns null rather than throwing for a path that is not there' {
        # A 404 on an item fetch is a RESULT, not an exception.
        $text = Get-AzDoPipelineYaml -Organisation $script:Where.Organisation -Project $script:Where.Project -RepositoryName 'pipelines-main' -Path 'pipelines/definitely-absent.yml'
        $text | Should-BeNull
    }

    It 'returns null for a repository that does not exist' {
        $text = Get-AzDoPipelineYaml -Organisation $script:Where.Organisation -Project $script:Where.Project -RepositoryName 'no-such-repo' -Path 'a.yml'
        $text | Should-BeNull
    }

    It 'builds a graph with nodes and edges' {
        @($script:Graph.nodes).Count | Should-BeGreaterThan 0
        @($script:Graph.edges).Count | Should-BeGreaterThan 0
    }

    It 'gives every yaml node a repo and a path under repos/' {
        foreach ($node in @($script:Graph.nodes | Where-Object kind -eq 'yaml')) {
            $node.repo | Should-NotBeNull
            $node.path | Should-MatchString '^repos/'
        }
    }

    It 'emits one node per identity, never one per traversal arrival' {
        $ids = @($script:Graph.nodes.id)
        @($ids | Sort-Object -Unique).Count | Should-Be $ids.Count
    }

    It 'keeps a shared template as ONE node with in-degree above one' {
        $incoming = @{}
        foreach ($edge in $script:Graph.edges) {
            if (-not $incoming.ContainsKey($edge.to)) { $incoming[$edge.to] = 0 }
            $incoming[$edge.to]++
        }
        @($incoming.Values | Where-Object { $_ -gt 1 }).Count | Should-BeGreaterThan 0
    }

    It 'emits no repository node for a repository nothing references' {
        # Repository nodes come from resources.repositories and checkout, never
        # from the repositories endpoint.
        $referenced = @($script:Graph.edges |
                Where-Object { $_.kind -in 'repositoryResource', 'checkout' } |
                ForEach-Object { $_.to })
        foreach ($node in @($script:Graph.nodes | Where-Object kind -eq 'repo')) {
            $referenced | Should-ContainCollection $node.id
        }
    }

    It 'carries a ref on every edge except definition edges' {
        foreach ($edge in @($script:Graph.edges | Where-Object kind -ne 'definition')) {
            $edge.ref | Should-NotBeNull
        }
        foreach ($edge in @($script:Graph.edges | Where-Object kind -eq 'definition')) {
            $edge.PSObject.Properties.Name | Should-NotContainCollection 'ref'
        }
    }

    It 'keeps both edges of the cycle and still terminates' {
        $cycleEdges = @($script:Graph.edges | Where-Object { $_.from -match 'cycle-' -and $_.to -match 'cycle-' })
        $cycleEdges.Count | Should-BeGreaterThanOrEqual 2
    }

    It 'reports unresolved references with a specific reason, never a bare one' {
        # file-not-found and alias-not-declared need different fixes, so
        # reporting both as "not found" tells the reader nothing.
        foreach ($edge in @($script:Graph.edges | Where-Object kind -eq 'unresolved')) {
            @('file-not-found', 'alias-not-declared') | Should-ContainCollection $edge.reason
            $edge.ref | Should-NotBeNull
            $edge.refKind | Should-NotBeNull
        }
    }

    It 'produces the same graph twice, so it can be diffed' {
        $again = Get-AzDoPipelineDependencyGraph -Organisation $script:Where.Organisation -Project $script:Where.Project -WarningAction SilentlyContinue
        $first = $script:Graph | Export-AzDoPipelineDependencyGraph -Format Json
        $second = $again | Export-AzDoPipelineDependencyGraph -Format Json
        $second | Should-Be $first
    }
}
