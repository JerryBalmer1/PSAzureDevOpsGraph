# Seals on a FINISHED iteration. Everything here is tagged PreTag, runs
# immediately before a tag and nowhere else, and is excluded from the default
# Test task so a half-finished iteration can still build green.
#
# What belongs here: claims no unit test can make, because they are about what
# the code must never do or about agreement between documents and code.

BeforeAll {
    . "$PSScriptRoot/TestHelpers.ps1"
    $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = "$script:RepositoryRoot/src/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psd1"
    $script:Manifest = Import-PowerShellDataFile -LiteralPath $script:ManifestPath -ErrorAction Stop
}

Describe 'Pre-tag seals' -Tag 'PreTag' {

    It 'reports a manifest version that no tag already claims' {
        $version = $script:Manifest.ModuleVersion
        $version | Should-MatchString '^\d+\.\d+\.\d+$'

        $existing = @(git -C $script:RepositoryRoot tag --list "v$version")
        @($existing).Count | Should-Be 0 -Because "v$version must not already exist"
    }

    It 'names no path in the README that does not exist' {
        $readme = Get-Content -LiteralPath "$script:RepositoryRoot/README.md" -Raw
        foreach ($match in [regex]::Matches($readme, '(?m)^\s*[-*]?\s*`(src/[^`]+|tests/[^`]+|build\.ps1)`')) {
            $path = Join-Path $script:RepositoryRoot $match.Groups[1].Value
            (Test-Path -LiteralPath $path) | Should-BeTrue -Because "the README names $($match.Groups[1].Value)"
        }
    }

    It 'ships no credential and no credential file' {
        $offenders = @(Get-ChildItem -LiteralPath $script:RepositoryRoot -Recurse -File -Force |
                Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.Extension -in '.pat', '.txt' -and $_.Name -match 'pat' })
        @($offenders).Count | Should-Be 0
    }

    It 'shells out to nothing the module says it never runs' {
        # src/ reads Azure DevOps over HTTPS and parses YAML. It runs no native
        # executable at all, which is a claim worth sealing rather than assuming.
        foreach ($file in Get-ChildItem -LiteralPath "$script:RepositoryRoot/src" -Filter *.ps1 -Recurse -File) {
            $errors = $null
            $tokens = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $tokens, [ref] $errors)
            @($errors).Count | Should-Be 0 -Because "$($file.Name) must parse"

            $native = $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -and
                    $node.GetCommandName() -match '\.(exe|cmd|bat)$'
                }, $true)
            @($native).Count | Should-Be 0 -Because "$($file.Name) must run no native executable"
        }
    }

    It 'keeps the export list agreeing in all four places' {
        $files = @((Get-ChildItem -LiteralPath "$script:RepositoryRoot/src/PSAzureDevOpsGraph/Public" -Filter *.ps1 -File).BaseName | Sort-Object)
        $manifest = @($script:Manifest.FunctionsToExport | Sort-Object)
        $loader = Get-Content -LiteralPath "$script:RepositoryRoot/src/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psm1" -Raw
        $built = Get-Content -LiteralPath "$script:RepositoryRoot/output/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psm1" -Raw -ErrorAction SilentlyContinue

        $manifest | Should-BeCollection -Expected $files
        foreach ($name in $files) {
            $loader | Should-MatchString ([regex]::Escape("'$name'"))
            if ($built) { $built | Should-MatchString ([regex]::Escape("'$name'")) }
        }
    }
}
