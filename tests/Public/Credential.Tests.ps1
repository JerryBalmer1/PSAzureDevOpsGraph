#Requires -Version 7.2

BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    $script:Module = Import-ModuleUnderTest
    $script:SavedPat = $env:AZDO_PAT
}

AfterAll {
    $env:AZDO_PAT = $script:SavedPat
}

Describe 'The credential rule' {

    Context 'when AZDO_PAT is absent' {

        BeforeEach { $env:AZDO_PAT = $null }
        AfterEach { $env:AZDO_PAT = $script:SavedPat }

        It 'fails <Command> by naming the variable, rather than prompting or falling back' -ForEach @(
            @{ Command = 'Get-AzDoRepository' }
            @{ Command = 'Get-AzDoPipeline' }
            @{ Command = 'Get-AzDoPipelineDependencyGraph' }
        ) {
            { & $Command -Organisation someorg -Project someproject -ErrorAction Stop } |
                Should-Throw -ExceptionMessage '*AZDO_PAT*'
        }

        It 'fails Get-AzDoPipelineYaml by naming the variable' {
            { Get-AzDoPipelineYaml -Organisation someorg -Project someproject -RepositoryName r -Path p.yml -ErrorAction Stop } |
                Should-Throw -ExceptionMessage '*AZDO_PAT*'
        }
    }

    It 'takes no PAT, token or credential parameter on any exported command' {
        # A value passed as a parameter ends up in PSReadLine history, in
        # Start-Transcript output and in the ScriptBlock logging event log.
        # Anchored. An unanchored 'pat' matches the parameter -Path, which is
        # a false positive that makes the assertion look strict while grading
        # something else.
        foreach ($command in (Get-Command -Module PSAzureDevOpsGraph)) {
            $offending = @($command.Parameters.Keys | Where-Object { $_ -match '(?i)^(pat|token|credential|secret|password)$' })
            $offending.Count | Should-Be 0 -Because "$($command.Name) must take the PAT from the environment only"
        }
    }

    It 'exports no command whose verb writes' {
        # A module that walks an organisation's pipelines is exactly the kind of
        # tool run with a high-privilege token.
        $writing = @('New', 'Set', 'Remove', 'Start', 'Stop', 'Invoke', 'Update', 'Add', 'Clear', 'Restart', 'Publish', 'Queue')
        foreach ($command in (Get-Command -Module PSAzureDevOpsGraph)) {
            $verb = ($command.Name -split '-')[0]
            $writing | Should-NotContainCollection $verb
        }
    }

    It 'parses YAML with no credential at all' {
        $env:AZDO_PAT = $null
        @(Get-AzDoPipelineReference -Yaml 'steps: [ { template: t.yml } ]').Count | Should-Be 1
        $env:AZDO_PAT = $script:SavedPat
    }
}
