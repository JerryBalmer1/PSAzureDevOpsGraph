#Requires -Version 7.2
BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:Module = Import-BuiltModule
    $script:Manifest = Import-PowerShellDataFile -LiteralPath (Get-BuiltModuleManifest) -ErrorAction Stop
    $script:Psm1 = Get-Content -LiteralPath (Join-Path (Split-Path -Parent (Get-BuiltModuleManifest)) 'PSAzureDevOpsGraph.psm1') -Raw
    $script:SourceRoot = Join-Path $script:RepositoryRoot 'src/PSAzureDevOpsGraph'
}

Describe 'The built module' {

    It 'exports exactly what the manifest declares' {
        $exported = @($script:Module.ExportedFunctions.Keys | Sort-Object)
        $declared = @($script:Manifest.FunctionsToExport | Sort-Object)
        $exported | Should-BeCollection $declared
    }

    It 'exports exactly the Public file basenames' {
        $files = @(Get-ChildItem -LiteralPath "$script:SourceRoot/Public" -Filter *.ps1 -File | ForEach-Object BaseName | Sort-Object)
        @($script:Manifest.FunctionsToExport | Sort-Object) | Should-BeCollection $files
    }

    It 'keeps the committed dev loader in step with the manifest' {
        # The fourth corner of the three-way agreement, which the conformance
        # suite does not grade.
        $loader = Get-Content -LiteralPath "$script:SourceRoot/PSAzureDevOpsGraph.psm1" -Raw
        foreach ($name in $script:Manifest.FunctionsToExport) {
            $loader | Should-MatchString ([regex]::Escape("'$name'"))
        }
    }

    It 'says it is generated' {
        $script:Psm1 | Should-MatchString '(?i)auto-generated'
    }

    It 'assigns $script:ModuleRoot from $PSScriptRoot as code, not in a comment' {
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:Psm1, [ref] $null, [ref] $errors)
        $assignments = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -eq '$script:ModuleRoot' -and
                $node.Right.Extent.Text -match '\$PSScriptRoot'
            }, $true)
        @($assignments).Count | Should-BeGreaterThan 0
    }

    It 'calls Export-ModuleMember with every exported name as a string constant' {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:Psm1, [ref] $null, [ref] $null)
        $calls = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Export-ModuleMember'
            }, $true)
        @($calls).Count | Should-Be 1

        $constants = $calls[0].FindAll({
                param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
            }, $true) | ForEach-Object { $_.Value }
        foreach ($name in $script:Manifest.FunctionsToExport) {
            $constants | Should-ContainCollection $name
        }
    }

    It 'carries the functions defined in nested Private subfolders' {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:Psm1, [ref] $null, [ref] $null)
        $defined = $ast.FindAll({
                param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true) | ForEach-Object { $_.Name }

        foreach ($file in Get-ChildItem -LiteralPath "$script:SourceRoot/Private" -Filter *.ps1 -Recurse -File) {
            $defined | Should-ContainCollection $file.BaseName
        }
    }

    It 'copied the culture directory, or Get-Help finds no about_ topic' {
        $topic = Join-Path (Split-Path -Parent (Get-BuiltModuleManifest)) 'en-US/about_PSAzureDevOpsGraph.help.txt'
        Test-Path -LiteralPath $topic | Should-BeTrue
    }

    It 'exports nothing implicitly' {
        foreach ($key in 'FunctionsToExport', 'CmdletsToExport', 'VariablesToExport', 'AliasesToExport') {
            $script:Manifest[$key] | Should-NotContainCollection '*'
        }
    }

    It 'declares CompatiblePSEditions and a GUID that parses' {
        $script:Manifest.CompatiblePSEditions | Should-ContainCollection 'Core'
        # There is no Should-NotThrow. To assert something does not throw, call
        # it: an exception fails the test on its own.
        ([guid] $script:Manifest.GUID) | Should-NotBeNull
    }
}

Describe 'The exported surface' {

    It 'gives every exported command comment-based help with a synopsis' {
        foreach ($name in $script:Module.ExportedFunctions.Keys) {
            $help = Get-Help $name -ErrorAction Stop
            # There is no Should-NotBeNullOrEmpty. Compare, do not pipe an
            # empty value into an assertion that then receives nothing.
            [string]::IsNullOrWhiteSpace($help.Synopsis) | Should-BeFalse -Because "$name needs a .SYNOPSIS"
        }
    }

    It 'begins no command with a writing verb, because the module is read-only' {
        # Enumerating the surface and asserting on the verbs is the testable
        # form of the read-only constraint.
        $writing = @('New', 'Set', 'Remove', 'Start', 'Stop', 'Restart', 'Update', 'Add', 'Clear', 'Reset', 'Submit', 'Push', 'Publish', 'Invoke')
        foreach ($name in $script:Module.ExportedFunctions.Keys) {
            $writing | Should-NotContainCollection ($name -split '-')[0]
        }
    }

    It 'names every exported command with the module prefix' {
        foreach ($name in $script:Module.ExportedFunctions.Keys) {
            $name | Should-MatchString '^[A-Z][a-z]+-AzDo'
        }
    }
}
