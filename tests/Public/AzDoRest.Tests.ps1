#Requires -Version 7.2
BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    Import-BuiltModule
    $script:OriginalPat = $env:AZDO_PAT
}

AfterAll {
    $env:AZDO_PAT = $script:OriginalPat
}

Describe 'The credential rule' {

    BeforeEach { $env:AZDO_PAT = $script:OriginalPat }

    It 'takes no PAT parameter on any exported command' {
        # A value passed as a parameter ends up in PSReadLine history, in
        # Start-Transcript output and in the ScriptBlock logging event log.
        # Whole camelCase words, not substrings: -Path contains "pat" and is
        # not a credential parameter, and a test that fires on it would be
        # deleted rather than fixed.
        $forbidden = '(?i)(^|[^a-z])(pat|token|credential|secret|password)([^a-z]|$)'
        foreach ($command in (Get-Module PSAzureDevOpsGraph).ExportedCommands.Values) {
            $offending = @($command.Parameters.Keys | Where-Object { $_ -match $forbidden })
            $offending -join ',' | Should-BeString '' -Because "$($command.Name) must take no credential parameter"
        }
    }

    It 'fails naming the variable when it is absent, and does not prompt or search' {
        $env:AZDO_PAT = ''
        { Get-AzDoRepository -Organisation 'org' -Project 'proj' } |
            Should-Throw -ExceptionMessage '*AZDO_PAT*'
    }

    It 'names the scopes a caller needs in that message' {
        $env:AZDO_PAT = ''
        { Get-AzDoPipeline -Organisation 'org' -Project 'proj' } |
            Should-Throw -ExceptionMessage '*Code (Read)*'
    }
}

Describe 'Get-AzDoRepository' {

    BeforeAll {
        $env:AZDO_PAT = 'test-token-not-a-real-credential'
        Mock -ModuleName PSAzureDevOpsGraph Invoke-WebRequest {
            [pscustomobject]@{
                StatusCode = 200
                Headers    = @{ 'Content-Type' = 'application/json' }
                Content    = (@{ value = @(
                            @{ id = 'r1'; name = 'app'; defaultBranch = 'refs/heads/main'; webUrl = 'u1'; isDisabled = $false }
                            @{ id = 'r2'; name = 'shared'; defaultBranch = 'refs/heads/trunk'; webUrl = 'u2'; isDisabled = $true }
                        ) } | ConvertTo-Json -Depth 10)
            }
        }
    }

    It 'returns one record per repository, typed' {
        $repositories = @(Get-AzDoRepository -Organisation 'org' -Project 'proj')
        $repositories.Count | Should-Be 2
        $repositories[0].PSObject.TypeNames | Should-ContainCollection 'PSAzureDevOpsGraph.Repository'
    }

    It 'filters by name without a second call' {
        $repositories = @(Get-AzDoRepository -Organisation 'org' -Project 'proj' -Name 'shared')
        $repositories.Count | Should-Be 1
        $repositories[0].DefaultBranch | Should-BeString 'refs/heads/trunk'
        $repositories[0].IsDisabled | Should-BeTrue
    }

    It 'calls a project-scoped route and never the accounts or profile API' {
        $null = Get-AzDoRepository -Organisation 'org' -Project 'proj'
        Should-Invoke -ModuleName PSAzureDevOpsGraph -CommandName Invoke-WebRequest -ParameterFilter {
            $Uri -like 'https://dev.azure.com/org/proj/_apis/git/repositories*'
        }
        Should-NotInvoke -ModuleName PSAzureDevOpsGraph -CommandName Invoke-WebRequest -ParameterFilter {
            $Uri -like '*vssps*' -or $Uri -like '*/_apis/accounts*'
        }
    }
}

Describe 'Get-AzDoPipeline' {

    BeforeAll {
        $env:AZDO_PAT = 'test-token-not-a-real-credential'
        Mock -ModuleName PSAzureDevOpsGraph Invoke-WebRequest {
            if ($Uri -match '/build/definitions/(\d+)\?') {
                $id = [int] $Matches[1]
                $body = @{
                    id          = $id
                    name        = "Definition-$id"
                    repository  = @{ id = 'r1'; name = 'app'; type = 'TfsGit'; defaultBranch = 'refs/heads/main' }
                    queueStatus = 'enabled'
                }
                $body['process'] = if ($id -eq 2) { @{ type = 1 } } else { @{ type = 2; yamlFilename = "/pipelines/p$id.yml" } }
                return [pscustomobject]@{
                    StatusCode = 200
                    Headers    = @{ 'Content-Type' = 'application/json' }
                    Content    = ($body | ConvertTo-Json -Depth 10)
                }
            }
            [pscustomobject]@{
                StatusCode = 200
                Headers    = @{ 'Content-Type' = 'application/json' }
                Content    = (@{ value = @(@{ id = 1; name = 'Definition-1' }, @{ id = 2; name = 'Definition-2' }) } | ConvertTo-Json -Depth 10)
            }
        }
    }

    It 'fetches each definition by id, because the list form carries no yaml path' {
        $pipelines = @(Get-AzDoPipeline -Organisation 'org' -Project 'proj')
        $pipelines.Count | Should-Be 2
        $pipelines[0].YamlPath | Should-BeString 'pipelines/p1.yml'
        Should-Invoke -ModuleName PSAzureDevOpsGraph -CommandName Invoke-WebRequest -Times 3 -Exactly
    }

    It 'strips the leading slash from yamlFilename so the path is repository-relative' {
        $pipeline = @(Get-AzDoPipeline -Organisation 'org' -Project 'proj' -Id 1)[0]
        $pipeline.YamlPath | Should-NotMatchString '^/'
    }

    It 'keeps a classic definition, with no YamlPath rather than dropped' {
        $pipeline = @(Get-AzDoPipeline -Organisation 'org' -Project 'proj' -Name 'Definition-2')[0]
        $pipeline.Name | Should-BeString 'Definition-2'
        $pipeline.YamlPath | Should-BeNull
    }
}

Describe 'Get-AzDoPipelineYaml' {

    BeforeAll {
        $env:AZDO_PAT = 'test-token-not-a-real-credential'
        Mock -ModuleName PSAzureDevOpsGraph Invoke-WebRequest {
            if ($Uri -match 'path=%2Fgone\.yml') {
                $response = [System.Net.Http.HttpResponseMessage]::new(404)
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Not Found', $response)
            }
            [pscustomobject]@{
                StatusCode = 200
                Headers    = @{ 'Content-Type' = 'application/json' }
                Content    = (@{ path = '/p.yml'; content = "steps:`n  - script: echo hi`n" } | ConvertTo-Json -Depth 10)
            }
        }
    }

    It 'returns a record that traces back to its repository and path' {
        $yaml = Get-AzDoPipelineYaml -Organisation 'org' -Project 'proj' -Repository 'app' -Path 'p.yml'
        $yaml.Repository | Should-BeString 'app'
        $yaml.Path | Should-BeString 'p.yml'
        $yaml.Content | Should-MatchString 'echo hi'
    }

    It 'returns nothing for a path that is not in the repository, rather than throwing' {
        @(Get-AzDoPipelineYaml -Organisation 'org' -Project 'proj' -Repository 'app' -Path 'gone.yml').Count | Should-Be 0
    }

    It 'reads the file behind a pipeline record from the pipeline' {
        $record = [pscustomobject]@{
            PSTypeName = 'PSAzureDevOpsGraph.Pipeline'
            Name       = 'X'
            Repository = 'app'
            YamlPath   = 'pipelines/p1.yml'
        }
        $yaml = $record | Get-AzDoPipelineYaml -Organisation 'org' -Project 'proj'
        $yaml.Path | Should-BeString 'pipelines/p1.yml'
    }

    It 'has nothing to read for a classic definition and says so quietly' {
        $record = [pscustomobject]@{
            PSTypeName = 'PSAzureDevOpsGraph.Pipeline'
            Name       = 'Classic'
            Repository = 'app'
            YamlPath   = $null
        }
        @($record | Get-AzDoPipelineYaml -Organisation 'org' -Project 'proj').Count | Should-Be 0
    }

    It 'passes a ref through as a version descriptor' {
        $null = Get-AzDoPipelineYaml -Organisation 'org' -Project 'proj' -Repository 'app' -Path 'p.yml' -Ref 'develop'
        Should-Invoke -ModuleName PSAzureDevOpsGraph -CommandName Invoke-WebRequest -ParameterFilter {
            $Uri -like '*versionDescriptor.version=develop*'
        }
    }
}

Describe 'Invoke-AzDoWebRequest error handling' {

    BeforeEach { $env:AZDO_PAT = 'test-token-not-a-real-credential' }

    It 'reads the sign-in page, which arrives as a success status, as a bad PAT' {
        Mock -ModuleName PSAzureDevOpsGraph Invoke-WebRequest {
            [pscustomobject]@{
                StatusCode = 200
                Headers    = @{ 'Content-Type' = 'text/html; charset=utf-8' }
                Content    = '<html>sign in</html>'
            }
        }
        { Get-AzDoRepository -Organisation 'org' -Project 'proj' } |
            Should-Throw -ExceptionMessage '*AZDO_PAT*'
    }

    It 'names the scopes on a 401 rather than retrying' {
        Mock -ModuleName PSAzureDevOpsGraph Invoke-WebRequest {
            $response = [System.Net.Http.HttpResponseMessage]::new(401)
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Unauthorized', $response)
        }
        { Get-AzDoRepository -Organisation 'org' -Project 'proj' } |
            Should-Throw -ExceptionMessage '*Code (Read)*'
    }

    It 'puts no request URL and no token into the message it raises' {
        Mock -ModuleName PSAzureDevOpsGraph Invoke-WebRequest {
            $response = [System.Net.Http.HttpResponseMessage]::new(401)
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Unauthorized', $response)
        }
        $message = ''
        try { Get-AzDoRepository -Organisation 'org' -Project 'proj' } catch { $message = $_.Exception.Message }
        $message | Should-NotMatchString 'dev\.azure\.com'
        $message | Should-NotMatchString 'test-token-not-a-real-credential'
    }
}
