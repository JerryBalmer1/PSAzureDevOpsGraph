#Requires -Version 7.2
<#
    Reads a real Azure DevOps project, read-only. Skipped when $env:AZDO_PAT is
    unset - and skipped LOUDLY: a layer that reports success where nothing could
    contradict it is worse than one that says it did not run.
#>
BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    Import-BuiltModule

    $script:HasPat = -not [string]::IsNullOrWhiteSpace($env:AZDO_PAT)
    if (-not $script:HasPat) {
        Write-Warning 'AZDO_PAT is not set. The Integration layer graded nothing in this run.'
    }
    $script:Organisation = 'jlbalmerjr1'
    $script:Project = 'ClaudeTesting'
}

Describe 'A live project' -Tag 'Integration', 'RequiresPat' -Skip:([string]::IsNullOrWhiteSpace($env:AZDO_PAT)) {

    It 'lists repositories over a project-scoped route' {
        $repositories = @(Get-AzDoRepository -Organisation $script:Organisation -Project $script:Project)
        $repositories.Count | Should-BeGreaterThan 0
        $repositories[0].Id | Should-NotBeNull
    }

    It 'lists definitions, each carrying the repository and path of its YAML' {
        $pipelines = @(Get-AzDoPipeline -Organisation $script:Organisation -Project $script:Project)
        $pipelines.Count | Should-BeGreaterThan 0
        @($pipelines | Where-Object YamlPath).Count | Should-BeGreaterThan 0
    }

    It 'reads the YAML behind a definition and parses references from it' {
        $pipeline = @(Get-AzDoPipeline -Organisation $script:Organisation -Project $script:Project |
                Where-Object YamlPath)[0]
        $yaml = $pipeline | Get-AzDoPipelineYaml -Organisation $script:Organisation -Project $script:Project
        [string]::IsNullOrWhiteSpace($yaml.Content) | Should-BeFalse

        # Parsing is a separate question from resolution, and needs nothing else.
        $null = @($yaml | Get-AzDoPipelineReference)
    }

    It 'returns nothing rather than throwing for a path that is not there' {
        $repository = @(Get-AzDoRepository -Organisation $script:Organisation -Project $script:Project)[0]
        @(Get-AzDoPipelineYaml -Organisation $script:Organisation -Project $script:Project `
                -Repository $repository.Name -Path 'no/such/file-4f3a9b.yml').Count | Should-Be 0
    }
}
