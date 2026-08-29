#requires -Modules Pester

BeforeAll {
    $script:ModuleRoot   = Join-Path $PSScriptRoot '..' 'src' 'PSAzureDevOpsGraph'
    $script:ManifestPath = Join-Path $script:ModuleRoot 'PSAzureDevOpsGraph.psd1'
    $script:RepoRoot     = Join-Path $PSScriptRoot '..'
    Import-Module $script:ManifestPath -Force

    $script:Expected = @(
        'Get-AzDoRepository'
        'Get-AzDoPipeline'
        'Get-AzDoPipelineYaml'
        'Get-AzDoPipelineReference'
        'Resolve-AzDoPipelineReference'
        'Get-AzDoPipelineDependencyGraph'
        'Export-AzDoPipelineDependencyGraph'
    )
}

Describe 'Module' {

    It 'has a valid manifest' {
        { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports exactly the documented command surface' {
        $actual = @((Get-Module PSAzureDevOpsGraph).ExportedFunctions.Keys)
        ($actual | Sort-Object) | Should -Be ($script:Expected | Sort-Object)
    }

    It 'exports no aliases, cmdlets or variables' {
        $m = Get-Module PSAzureDevOpsGraph
        @($m.ExportedAliases.Keys).Count   | Should -Be 0
        @($m.ExportedCmdlets.Keys).Count   | Should -Be 0
        @($m.ExportedVariables.Keys).Count | Should -Be 0
    }

    It 'gives every exported command comment-based help with a synopsis' {
        foreach ($name in $script:Expected) {
            $help = Get-Help $name -ErrorAction Stop
            $help.Synopsis | Should -Not -BeNullOrEmpty -Because "$name should be documented"
            $help.Synopsis | Should -Not -Match '^\s*$'
        }
    }

    It 'gives every exported command at least one example' {
        foreach ($name in $script:Expected) {
            $help = Get-Help $name -ErrorAction Stop
            @($help.Examples.Example).Count | Should -BeGreaterThan 0 -Because "$name should show how to use it"
        }
    }
}

Describe 'Read-only guarantees' {

    It 'exports no command whose verb writes' {
        # The brief forbids queueing, creating, updating and deleting -- so the
        # module must not even have a command shaped like one.
        $writing = 'New', 'Set', 'Remove', 'Start', 'Invoke', 'Add', 'Update',
                   'Delete', 'Clear', 'Stop', 'Restart', 'Submit', 'Push', 'Write'

        foreach ($name in $script:Expected) {
            ($name -split '-')[0] | Should -Not -BeIn $writing
        }
    }

    It 'issues no HTTP verb other than Get anywhere in the source' {
        $sources = Get-ChildItem -Path $script:ModuleRoot -Recurse -Filter '*.ps1' -File
        $sources.Count | Should -BeGreaterThan 0

        foreach ($file in $sources) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            $text | Should -Not -Match "(?i)-Method\s+['`"]?(Post|Put|Patch|Delete)\b" `
                -Because "$($file.Name) must not make a writing request"
        }
    }

    It 'never names a pipeline run or queue endpoint' {
        $sources = Get-ChildItem -Path $script:ModuleRoot -Recurse -Filter '*.ps1' -File
        foreach ($file in $sources) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            $text | Should -Not -Match '(?i)/runs\b|queueBuild|_apis/build/builds\s*''' `
                -Because "$($file.Name) must not reach a queueing route"
        }
    }
}

Describe 'Credential handling' {

    It 'takes the token from AZDO_PAT and from nowhere else' {
        $sources = Get-ChildItem -Path $script:ModuleRoot -Recurse -Filter '*.ps1' -File
        $mentions = $sources | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'AZDO_PAT' }
        @($mentions).Count | Should -Be 1 -Because 'one place should read the credential'
    }

    It 'exposes no parameter that could carry a token' {
        foreach ($name in $script:Expected) {
            $command = Get-Command $name
            foreach ($parameter in $command.Parameters.Keys) {
                $parameter | Should -Not -Match '(?i)^(Pat|Token|Password|Secret|Credential|ApiKey|AccessToken)$' `
                    -Because "$name must not accept a credential as a parameter"
            }
        }
    }

    It 'fails with a message naming the variable when it is absent' {
        $saved = $env:AZDO_PAT
        try {
            Remove-Item Env:\AZDO_PAT -ErrorAction SilentlyContinue
            { Get-AzDoRepository -Organisation 'x' -Project 'y' } |
                Should -Throw -ExpectedMessage '*AZDO_PAT*'
        }
        finally { if ($saved) { $env:AZDO_PAT = $saved } }
    }

    It 'does not prompt or read a credential from a file' {
        $sources = Get-ChildItem -Path $script:ModuleRoot -Recurse -Filter '*.ps1' -File
        foreach ($file in $sources) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            $text | Should -Not -Match '(?i)Read-Host|Get-Credential' `
                -Because "$($file.Name) must not prompt for a credential"
        }
    }

    It 'commits no file that looks like a stored token' {
        $suspects = Get-ChildItem -Path $script:RepoRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.Name -match '(?i)\.pat$|^pat\.txt$|^AzDoPAT\.txt$' }
        @($suspects).Count | Should -Be 0
    }
}

Describe 'Export-AzDoPipelineDependencyGraph' {

    BeforeAll {
        $script:Graph = [pscustomobject]@{
            version      = 1
            organisation = 'org'
            project      = 'proj'
            generatedBy  = 'test'
            nodes        = @(
                [pscustomobject]@{ id = 'repo:a';       kind = 'repo';     name = 'a' }
                [pscustomobject]@{ id = 'pipeline:p';   kind = 'pipeline'; name = 'p' }
                [pscustomobject]@{ id = 'yaml:a/x.yml'; kind = 'yaml';     name = 'x.yml'; repo = 'a'; path = 'repos/a/x.yml' }
            )
            edges        = @(
                [pscustomobject]@{ from = 'pipeline:p'; to = 'yaml:a/x.yml'; kind = 'definition' }
                [pscustomobject]@{ from = 'yaml:a/x.yml'; to = 'unresolved:z.yml'; kind = 'unresolved'
                                   ref = 'z.yml'; refKind = 'template'; reason = 'missing' }
            )
        }
    }

    It 'writes JSON that round-trips' {
        $json = $script:Graph | Export-AzDoPipelineDependencyGraph -Format Json
        $back = $json | ConvertFrom-Json
        $back.version         | Should -Be 1
        @($back.nodes).Count   | Should -Be 3
        @($back.edges).Count   | Should -Be 2
    }

    It 'writes LF endings only' {
        $json = $script:Graph | Export-AzDoPipelineDependencyGraph -Format Json
        $json | Should -Not -Match "`r"
    }

    It 'writes DOT naming every node and edge' {
        $dot = $script:Graph | Export-AzDoPipelineDependencyGraph -Format Dot
        $dot | Should -Match 'digraph'
        $dot | Should -Match '"pipeline:p" -> "yaml:a/x.yml"'
    }

    It 'writes self-contained HTML with no external reference' {
        $html = $script:Graph | Export-AzDoPipelineDependencyGraph -Format Html
        $html | Should -Match '(?i)<!doctype html>'
        $html | Should -Not -Match '(?i)<script[^>]+src='
        $html | Should -Not -Match '(?i)https?://'
    }

    It 'shows unresolved references in the HTML' {
        $html = $script:Graph | Export-AzDoPipelineDependencyGraph -Format Html
        $html | Should -Match 'Unresolved references'
        $html | Should -Match 'missing'
    }

    It 'writes a file to disk' {
        $path = Join-Path $TestDrive 'g.json'
        $script:Graph | Export-AzDoPipelineDependencyGraph -Path $path
        Test-Path -LiteralPath $path | Should -BeTrue
        (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).project | Should -Be 'proj'
    }
}
