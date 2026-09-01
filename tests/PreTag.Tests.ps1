#Requires -Version 7.2
<#
    Seals on a FINISHED iteration. Everything here is tagged PreTag, runs
    immediately before a tag and nowhere else, and is excluded from the default
    Test task so a half-finished iteration can still build green.

    Declaring the PreTag task is not the same as having the gate: a repository
    with the task and no tagged test selects nothing, and -Task PreTag can then
    only ever throw its own guard. This file is what makes the task grade
    something.
#>
BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:Manifest = Import-PowerShellDataFile -LiteralPath "$script:RepositoryRoot/src/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psd1" -ErrorAction Stop
    $script:Version = [string] $script:Manifest.ModuleVersion
}

Describe 'Pre-tag seals' -Tag 'PreTag' {

    It 'has a worklog for the version the manifest reports' {
        Test-Path -LiteralPath "$script:RepositoryRoot/docs/worklog/v$script:Version.md" | Should-BeTrue
    }

    It 'has a changelog entry naming that version' {
        $changelog = Get-Content -LiteralPath "$script:RepositoryRoot/CHANGELOG.md" -Raw
        $changelog | Should-MatchString ([regex]::Escape($script:Version))
    }

    It 'names no relative path in a document that does not exist' {
        $documents = @(Get-ChildItem -LiteralPath $script:RepositoryRoot -Filter *.md -File) +
            @(Get-ChildItem -LiteralPath "$script:RepositoryRoot/docs" -Filter *.md -Recurse -File)

        $missing = [System.Collections.Generic.List[string]]::new()
        foreach ($document in $documents) {
            $text = Get-Content -LiteralPath $document.FullName -Raw
            foreach ($match in [regex]::Matches($text, '\]\((?<p>[^)#:]+)\)')) {
                $path = $match.Groups['p'].Value.Trim()
                if ($path -match '^(https?|mailto):' -or -not $path) { continue }
                $full = Join-Path (Split-Path -Parent $document.FullName) $path
                if (-not (Test-Path -LiteralPath $full)) {
                    $missing.Add("$($document.Name) -> $path")
                }
            }
        }
        $missing -join '; ' | Should-BeString ''
    }

    It 'contains no document that can publish by being followed' {
        # A runnable publish command in a document is a release nobody decided
        # to make.
        foreach ($document in Get-ChildItem -LiteralPath $script:RepositoryRoot -Filter *.md -Recurse -File) {
            if ($document.FullName -like '*\output\*') { continue }
            $text = Get-Content -LiteralPath $document.FullName -Raw
            $text | Should-NotMatchString '(?m)^\s*Publish-Module\b'
            $text | Should-NotMatchString '(?m)^\s*git\s+push\s+--tags'
        }
    }

    It 'issues no request in src that is not a GET' {
        # Structural, not textual: the assertion looks at the -Method argument
        # of every web call, so a comment quoting the line cannot satisfy it.
        $offending = [System.Collections.Generic.List[string]]::new()
        foreach ($file in Get-ChildItem -LiteralPath "$script:RepositoryRoot/src" -Filter *.ps1 -Recurse -File) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $null, [ref] $null)
            $calls = $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -in 'Invoke-WebRequest', 'Invoke-RestMethod'
                }, $true)

            foreach ($call in $calls) {
                $elements = $call.CommandElements
                for ($i = 0; $i -lt $elements.Count - 1; $i++) {
                    $element = $elements[$i]
                    if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and
                        $element.ParameterName -eq 'Method') {
                        $value = $elements[$i + 1].Extent.Text
                        if ($value -ne 'Get') {
                            $offending.Add("$($file.Name): -Method $value")
                        }
                    }
                }
            }
        }
        $offending -join '; ' | Should-BeString ''
    }

    It 'defines no function in src whose verb writes' {
        $offending = [System.Collections.Generic.List[string]]::new()
        $writing = @('New', 'Set', 'Remove', 'Start', 'Stop', 'Restart', 'Update', 'Clear', 'Reset', 'Submit', 'Publish', 'Deny', 'Approve')
        foreach ($file in Get-ChildItem -LiteralPath "$script:RepositoryRoot/src" -Filter *.ps1 -Recurse -File) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $null, [ref] $null)
            foreach ($function in $ast.FindAll({
                        param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                    }, $true)) {
                $verb = ($function.Name -split '-')[0]
                # New-AzDoReferenceRecord builds an in-memory object and reaches
                # nothing; the seal is about what the module does to Azure
                # DevOps, so only exported names are load-bearing here.
                if ($verb -in $writing -and $function.Name -in $script:Manifest.FunctionsToExport) {
                    $offending.Add($function.Name)
                }
            }
        }
        $offending -join '; ' | Should-BeString ''
    }

    It 'names no pipeline-run or write route anywhere in src' {
        $routes = @('/_apis/build/builds', '/runs?api-version', 'pipelines/{id}/runs')
        foreach ($file in Get-ChildItem -LiteralPath "$script:RepositoryRoot/src" -Filter *.ps1 -Recurse -File) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            foreach ($route in $routes) {
                $text | Should-NotMatchString ([regex]::Escape($route))
            }
        }
    }
}
