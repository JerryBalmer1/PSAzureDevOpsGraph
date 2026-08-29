#Requires -Version 7.2

BeforeAll {
    Import-Module "$PSScriptRoot/../output/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psd1" -Force

    $script:Sample = [pscustomobject]@{
        version      = 1
        organisation = 'org'
        project      = 'Proj'
        generatedBy  = 'Get-AzDoPipelineDependencyGraph'
        nodes        = @(
            @{ id = 'pipeline:one'; kind = 'pipeline'; name = 'one' }
            @{ id = 'yaml:main/a.yml'; kind = 'yaml'; name = 'a.yml'; repo = 'main'; path = 'repos/main/a.yml' }
            @{ id = 'repo:main'; kind = 'repo'; name = 'main' }
        )
        edges        = @(
            @{ from = 'pipeline:one'; to = 'yaml:main/a.yml'; kind = 'definition' }
            @{ from = 'yaml:main/a.yml'; to = 'yaml:main/gone.yml'; kind = 'unresolved'
               ref  = 'gone.yml'; refKind = 'template'; reason = 'file-not-found' }
        )
        BackEdge     = @()
    }
}

Describe 'Export-AzDoPipelineDependencyGraph' {

    It 'writes JSON carrying only the six schema fields' {
        # The schema forbids additional properties at the top level, so the
        # in-memory BackEdge convenience field must not reach the file.
        $path = Join-Path $TestDrive 'graph.json'
        $null = $Sample | Export-AzDoPipelineDependencyGraph -Path $path
        $parsed = Get-Content $path -Raw | ConvertFrom-Json
        $keys = @($parsed.PSObject.Properties.Name | Sort-Object)
        ($keys -join ',') | Should-Be 'edges,generatedBy,nodes,organisation,project,version'
    }

    It 'round-trips nodes and edges' {
        $path = Join-Path $TestDrive 'graph2.json'
        $null = $Sample | Export-AzDoPipelineDependencyGraph -Path $path
        $parsed = Get-Content $path -Raw | ConvertFrom-Json
        @($parsed.nodes).Count | Should-Be 3
        @($parsed.edges).Count | Should-Be 2
    }

    It 'omits ref on a definition edge' {
        # A definition edge is a claim about the project, not about a file.
        $path = Join-Path $TestDrive 'graph3.json'
        $null = $Sample | Export-AzDoPipelineDependencyGraph -Path $path
        $parsed = Get-Content $path -Raw | ConvertFrom-Json
        $definition = @($parsed.edges | Where-Object kind -EQ 'definition')[0]
        $definition.PSObject.Properties.Name | Should-NotContainCollection 'ref'
    }

    It 'writes DOT with a node and an edge line' {
        $path = Join-Path $TestDrive 'graph.dot'
        $null = $Sample | Export-AzDoPipelineDependencyGraph -Path $path -Format Dot
        $text = Get-Content $path -Raw
        $text | Should-MatchString 'digraph pipelines'
        $text | Should-MatchString '"pipeline:one" -> "yaml:main/a.yml"'
    }

    It 'writes HTML that references nothing external' {
        $path = Join-Path $TestDrive 'graph.html'
        $null = $Sample | Export-AzDoPipelineDependencyGraph -Path $path -Format Html
        $text = Get-Content $path -Raw
        $text | Should-NotMatchString 'https?://'
        $text | Should-NotMatchString '@import'
        $text | Should-MatchString '<table'
    }

    It 'draws an unresolved target as a pseudo-node' {
        $path = Join-Path $TestDrive 'graph2.html'
        $null = $Sample | Export-AzDoPipelineDependencyGraph -Path $path -Format Html
        Get-Content $path -Raw | Should-MatchString 'pseudo-node'
    }
}

Describe 'Credential handling' {

    It 'fails by naming AZDO_PAT when the variable is absent' {
        InModuleScope PSAzureDevOpsGraph {
            $saved = $env:AZDO_PAT
            try {
                $env:AZDO_PAT = ''
                { Get-AzDoAuthHeader } | Should-Throw -ExceptionMessage '*AZDO_PAT*'
            }
            finally {
                $env:AZDO_PAT = $saved
            }
        }
    }

    It 'exposes no command with a Pat or Token parameter' {
        # A PAT passed as a parameter lands in PSReadLine history, in
        # Start-Transcript output, and in ScriptBlock logging.
        foreach ($command in (Get-Command -Module PSAzureDevOpsGraph)) {
            $names = @($command.Parameters.Keys)
            $names | Should-NotContainCollection 'Pat'
            $names | Should-NotContainCollection 'Token'
            $names | Should-NotContainCollection 'PersonalAccessToken'
        }
    }

    It 'exposes no command whose verb writes' {
        foreach ($command in (Get-Command -Module PSAzureDevOpsGraph)) {
            $verb = ($command.Name -split '-')[0]
            $verb | Should-NotBeString 'New' -CaseSensitive
            $verb | Should-NotBeString 'Set' -CaseSensitive
            $verb | Should-NotBeString 'Remove' -CaseSensitive
            $verb | Should-NotBeString 'Start' -CaseSensitive
            $verb | Should-NotBeString 'Invoke' -CaseSensitive
        }
    }
}

Describe 'REST surface' {

    It 'lists repositories from the project route' {
        $result = InModuleScope PSAzureDevOpsGraph {
            Mock Invoke-AzDoRestMethod {
                @([pscustomobject]@{ name = 'main'; id = 'r1'; defaultBranch = 'refs/heads/main' })
            }
            Get-AzDoRepository -Organisation 'org' -Project 'Proj'
        }
        @($result).Count | Should-Be 1
        $result[0].Name | Should-Be 'main'
    }

    It 'fetches each definition by id to learn its repository and path' {
        $result = InModuleScope PSAzureDevOpsGraph {
            Mock Invoke-AzDoRestMethod {
                if ($Single) {
                    [pscustomobject]@{
                        name       = 'p01'; id = 1
                        repository = [pscustomobject]@{ name = 'main'; id = 'r1' }
                        process    = [pscustomobject]@{ yamlFilename = 'pipelines/p01.yml' }
                    }
                }
                else { @([pscustomobject]@{ id = 1 }) }
            }
            Get-AzDoPipeline -Organisation 'org' -Project 'Proj'
        }
        @($result).Count | Should-Be 1
        $result[0].Path | Should-Be 'pipelines/p01.yml'
        $result[0].RepositoryName | Should-Be 'main'
    }

    It 'returns null rather than throwing when a file is absent' {
        $result = InModuleScope PSAzureDevOpsGraph {
            Mock Get-AzDoItemContent { $null }
            Get-AzDoPipelineYaml -Organisation 'org' -Project 'Proj' -RepositoryId 'r1' -Path 'nope.yml'
        }
        $result | Should-BeNull
    }
}
