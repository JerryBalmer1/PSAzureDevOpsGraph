#Requires -Version 7.2
<#
    Asserts on the BUILT module, not on source. output/ is the artifact users
    get and the only place the generated Export-ModuleMember exists.
#>

BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:Source = Join-Path $script:Root 'src/PSAzureDevOpsGraph'
    $script:Output = Join-Path $script:Root 'output/PSAzureDevOpsGraph'
    $script:Module = Import-ModuleUnderTest
    $script:Manifest = Import-PowerShellDataFile (Join-Path $script:Source 'PSAzureDevOpsGraph.psd1') -ErrorAction Stop
    $script:PublicNames = @(Get-ChildItem (Join-Path $script:Source 'Public') -Filter *.ps1 -File | Sort-Object Name).BaseName
}

Describe 'Three-way agreement' {

    It 'has the same set of Public filenames and FunctionsToExport' {
        # The build derives Export-ModuleMember from the filenames while the
        # manifest is written by hand. This is the seam where they drift.
        @($script:Manifest.FunctionsToExport | Sort-Object) | Should-BeCollection @($script:PublicNames | Sort-Object)
    }

    It 'exports at runtime exactly what the manifest declares' {
        @($script:Module.ExportedFunctions.Keys | Sort-Object) | Should-BeCollection @($script:Manifest.FunctionsToExport | Sort-Object)
    }

    It 'has a dev loader exporting the same set as the manifest' {
        # The fourth corner, which the conformance suite does not grade.
        $loader = Get-Content (Join-Path $script:Source 'PSAzureDevOpsGraph.psm1') -Raw
        foreach ($name in $script:Manifest.FunctionsToExport) {
            $loader | Should-MatchString ([regex]::Escape("'$name'"))
        }
    }

    It 'exports nothing implicitly' {
        # A key left unset defaults to a wildcard.
        foreach ($key in 'CmdletsToExport', 'VariablesToExport', 'AliasesToExport') {
            @($script:Manifest[$key]).Count | Should-Be 0
        }
        $script:Manifest.FunctionsToExport | Should-NotContainCollection '*'
    }

    It 'declares CompatiblePSEditions' {
        @($script:Manifest.CompatiblePSEditions).Count | Should-BeGreaterThan 0
    }

    It 'has a GUID that parses' {
        [guid]::Parse($script:Manifest.GUID) | Should-NotBeNull
    }

    It 'declares its runtime dependency, which is not the same list as the build one' {
        $names = @($script:Manifest.RequiredModules | ForEach-Object { $_['ModuleName'] })
        $names | Should-ContainCollection 'powershell-yaml'
    }
}

Describe 'Comment-based help' {

    It 'gives <Name> a synopsis' -ForEach @(
        (Get-ChildItem (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/PSAzureDevOpsGraph/Public') -Filter *.ps1 -File |
            ForEach-Object { @{ Name = $_.BaseName } })
    ) {
        $help = Get-Help $Name -ErrorAction Stop
        $help.Synopsis | Should-NotBeWhiteSpaceString
        $help.Synopsis | Should-NotBe $Name
    }
}

Describe 'The built artifact' -Skip:(-not (Test-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'output/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psm1'))) {

    BeforeAll {
        $script:Generated = Get-Content (Join-Path $script:Output 'PSAzureDevOpsGraph.psm1') -Raw
    }

    It 'says it is auto-generated' {
        $script:Generated | Should-MatchString '(?i)auto-generated'
    }

    It 'assigns $script:ModuleRoot from $PSScriptRoot as real code, not a comment' {
        # Emitted as code. A generated file is the one place a commented-out
        # line is cheapest to write by accident.
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:Generated, [ref] $null, [ref] $errors)
        @($errors).Count | Should-Be 0
        $assignments = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -match 'script:ModuleRoot' -and
                $node.Right.Extent.Text -match 'PSScriptRoot'
            }, $true)
        @($assignments).Count | Should-BeGreaterThan 0
    }

    It 'calls Export-ModuleMember listing every exported name as a string constant' {
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:Generated, [ref] $null, [ref] $errors)
        $calls = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Export-ModuleMember'
            }, $true)
        @($calls).Count | Should-Be 1
        $text = $calls[0].Extent.Text
        foreach ($name in $script:Manifest.FunctionsToExport) {
            $text | Should-MatchString ([regex]::Escape("'$name'"))
        }
    }

    It 'carries functions defined in nested Private subfolders' {
        foreach ($name in 'Invoke-AzDoRestMethod', 'Read-AzDoYamlReference', 'Find-AzDoGraphCycle', 'ConvertTo-AzDoGraphHtml') {
            $script:Generated | Should-MatchString "function $name"
        }
    }

    It 'has the culture directory copied beside it' {
        # The most commonly missed build step, because everything else works.
        Test-Path (Join-Path $script:Output 'en-US/about_PSAzureDevOpsGraph.help.txt') | Should-BeTrue
    }
}
