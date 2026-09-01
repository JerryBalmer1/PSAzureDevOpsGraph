BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:ManifestPath = Import-ModuleUnderTest
    $script:Manifest = Import-PowerShellDataFile -LiteralPath $script:ManifestPath -ErrorAction Stop
    $script:SourceRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/PSAzureDevOpsGraph'
}

Describe 'The built module' {

    It 'exports exactly the functions the manifest declares' {
        $exported = @((Get-Module PSAzureDevOpsGraph).ExportedFunctions.Keys | Sort-Object)
        $declared = @($script:Manifest.FunctionsToExport | Sort-Object)
        $exported | Should-BeCollection -Expected $declared
    }

    It 'agrees with the Public filenames' {
        $files = @((Get-ChildItem -LiteralPath "$script:SourceRoot/Public" -Filter *.ps1 -File).BaseName | Sort-Object)
        @($script:Manifest.FunctionsToExport | Sort-Object) | Should-BeCollection -Expected $files
    }

    It 'exports nothing implicitly' {
        foreach ($key in 'FunctionsToExport', 'CmdletsToExport', 'VariablesToExport', 'AliasesToExport') {
            $script:Manifest.ContainsKey($key) | Should-BeTrue
            @($script:Manifest[$key]) | Should-NotContainCollection -Expected '*'
        }
    }

    It 'declares CompatiblePSEditions' {
        @($script:Manifest.CompatiblePSEditions) | Should-ContainCollection -Expected 'Core'
    }

    It 'has a GUID that parses' {
        [guid]::Parse($script:Manifest.GUID) | Should-NotBeNull
    }

    It 'names no command with a writing verb' {
        # A module that walks an organisation's pipelines is exactly the kind of
        # thing run with a high-privilege token. Export- writes a local file and
        # is the only Data verb here.
        foreach ($name in (Get-Module PSAzureDevOpsGraph).ExportedFunctions.Keys) {
            @('New', 'Set', 'Remove', 'Start', 'Stop', 'Update', 'Add', 'Clear', 'Rename') |
                Should-NotContainCollection -Expected ($name -split '-')[0]
        }
    }

    It 'gives every exported function comment-based help with a synopsis' {
        foreach ($name in (Get-Module PSAzureDevOpsGraph).ExportedFunctions.Keys) {
            $help = Get-Help -Name $name -ErrorAction Stop
            $help.Synopsis | Should-NotBeEmptyString
            $help.Synopsis | Should-NotBeString -Expected $name
        }
    }

    It 'keeps the dev loader in step with the manifest' {
        $loader = Get-Content -LiteralPath "$script:SourceRoot/PSAzureDevOpsGraph.psm1" -Raw
        foreach ($name in $script:Manifest.FunctionsToExport) {
            $loader | Should-MatchString ([regex]::Escape("'$name'"))
        }
    }

    It 'reaches no network from any file in src, except through the one REST helper' {
        $offenders = @()
        foreach ($file in Get-ChildItem -LiteralPath $script:SourceRoot -Filter *.ps1 -Recurse -File) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            if ($text -match 'Invoke-WebRequest|Invoke-RestMethod' -and $file.Name -ne 'Invoke-AzDoRestMethod.ps1') {
                $offenders += $file.Name
            }
        }
        @($offenders).Count | Should-Be 0 -Because 'every call goes through Invoke-AzDoRestMethod'
    }

    It 'issues no write against Azure DevOps anywhere in src' {
        foreach ($file in Get-ChildItem -LiteralPath $script:SourceRoot -Filter *.ps1 -Recurse -File) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            $text | Should-NotMatchString "-Method\s+(Post|Put|Patch|Delete)"
        }
    }

    It 'declares its runtime dependency' {
        $required = @($script:Manifest.RequiredModules | Where-Object { $_.ModuleName -eq 'powershell-yaml' })
        $required.Count | Should-Be 1
    }
}
