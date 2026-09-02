#Requires -Version 7.2
<#
    Invoke-Build task file for PSAzureDevOpsGraph.

    The module ships as ONE generated .psm1 rather than as a tree that
    dot-sources at import time. Dot-sourcing costs a file open per function on
    every import, and it makes coverage measure the source tree rather than the
    thing that actually ships. The generated file is never edited and never
    committed; src/ is the source of truth.

    Run with: Invoke-Build            (Clean, Lint, Build, Test)
              Invoke-Build PreTag     (everything, plus the pre-tag checks)
#>

param(
    [string]$ModuleName = 'PSAzureDevOpsGraph',
    # Below this, the Test task throws. Reporting a number nobody acts on is the
    # same as not measuring.
    [int]$CoverageTarget = 70
)

Set-StrictMode -Version Latest

$script:Source     = "$BuildRoot/src/$ModuleName"
$script:OutputRoot = "$BuildRoot/output"
$script:Staged     = "$script:OutputRoot/$ModuleName"
$script:BuiltPsm1  = "$script:Staged/$ModuleName.psm1"
$script:Results    = "$BuildRoot/testResults"

# The default: what a bare 'Invoke-Build' does.
task . Clean, Lint, Build, Test

# ---------------------------------------------------------------------------

task Clean {
    foreach ($path in $script:OutputRoot, $script:Results) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
    }
}

task Lint {
    Import-Module PSScriptAnalyzer -ErrorAction Stop
    $settings = "$BuildRoot/PSScriptAnalyzerSettings.psd1"

    # Two passes rather than one blanket exclusion. The shipped code and the
    # tests are held to the full rule set; the build files are not, because
    # 'task' is Invoke-Build's own DSL and rewriting it to Add-BuildTask to
    # satisfy an alias rule would make the build file harder to read for no
    # gain. Narrowing the exception to the two files that need it keeps the
    # rule live everywhere it should be.
    $findings = @(
        Invoke-ScriptAnalyzer -Path "$BuildRoot/src" -Recurse -Settings $settings
        Invoke-ScriptAnalyzer -Path "$BuildRoot/tests" -Recurse -Settings $settings
        Invoke-ScriptAnalyzer -Path "$BuildRoot/build.ps1" -Settings $settings -ExcludeRule PSAvoidUsingCmdletAliases
        Invoke-ScriptAnalyzer -Path "$BuildRoot/PSAzureDevOpsGraph.build.ps1" -Settings $settings -ExcludeRule PSAvoidUsingCmdletAliases
    )

    if ($findings) {
        $findings | Format-Table Severity, ScriptName, Line, RuleName, Message -AutoSize | Out-String | Write-Host
        throw "PSScriptAnalyzer reported $($findings.Count) finding(s)."
    }
    Write-Host '    analyzer: clean'
}

task Build {
    $null = New-Item -ItemType Directory -Path $script:Staged -Force

    $public = @(Get-ChildItem "$script:Source/Public" -Filter '*.ps1' -File | Sort-Object Name)
    $private = @(Get-ChildItem "$script:Source/Private" -Filter '*.ps1' -File -Recurse | Sort-Object FullName)

    $builder = [System.Text.StringBuilder]::new()
    $null = $builder.AppendLine(@"
# ------------------------------------------------------------------------
# $ModuleName -- auto-generated. Do not edit.
#
# Assembled from src/$ModuleName by $ModuleName.build.ps1. Edit the files
# under src/ and rebuild; anything changed here is lost on the next build.
# ------------------------------------------------------------------------
#Requires -Version 7.2
Set-StrictMode -Version Latest

`$script:ModuleRoot = `$PSScriptRoot
"@)

    foreach ($file in ($private + $public)) {
        $null = $builder.AppendLine()
        $null = $builder.AppendLine("#region $($file.Directory.Name)/$($file.Name)")
        $null = $builder.AppendLine((Get-Content -LiteralPath $file.FullName -Raw).TrimEnd())
        $null = $builder.AppendLine('#endregion')
    }

    # Explicit, and generated from the files that exist rather than from a list
    # somebody has to remember to update.
    $exported = ($public.BaseName | ForEach-Object { "'$_'" }) -join ', '
    $null = $builder.AppendLine()
    $null = $builder.AppendLine("Export-ModuleMember -Function @($exported)")

    $text = ($builder.ToString() -replace "`r`n", "`n")
    [System.IO.File]::WriteAllText($script:BuiltPsm1, $text, [System.Text.UTF8Encoding]::new($false))

    Copy-Item -LiteralPath "$script:Source/$ModuleName.psd1" -Destination $script:Staged -Force

    $null = Test-ModuleManifest -Path "$script:Staged/$ModuleName.psd1"

    $tokens = $null; $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($script:BuiltPsm1, [ref]$tokens, [ref]$errors)
    if ($errors) { throw "Generated module does not parse:`n$(($errors | ForEach-Object Message) -join "`n")" }

    Write-Host "    built   : $script:BuiltPsm1 ($($public.Count) public, $($private.Count) private)"
}

task Test {
    Import-Module Pester -MinimumVersion 6.0 -ErrorAction Stop
    $null = New-Item -ItemType Directory -Path $script:Results -Force

    $config = New-PesterConfiguration
    $config.Run.Path         = "$BuildRoot/tests"
    $config.Run.PassThru     = $true
    $config.Output.Verbosity = 'Detailed'

    # PreTag-tagged tests are slow or need a network and are not part of the
    # ordinary loop; the PreTag task runs them.
    $config.Filter.ExcludeTag = @('PreTag', 'Integration')

    # v5 'Should -Be' is off: one assertion syntax per repository, so that a
    # failure message always reads the same way.
    $config.Should.DisableV5 = $true

    # Coverage is measured against the BUILT module, which is what ships. The
    # source tree would report on files that no import ever loads.
    $config.CodeCoverage.Enabled               = $true
    $config.CodeCoverage.Path                  = $script:BuiltPsm1
    $config.CodeCoverage.CoveragePercentTarget = $CoverageTarget
    $config.CodeCoverage.OutputPath            = "$script:Results/coverage.xml"

    $config.TestResult.Enabled    = $true
    $config.TestResult.OutputPath = "$script:Results/pester.xml"

    $result = Invoke-Pester -Configuration $config

    # Throw, never exit: an exit here would take the whole build host with it and
    # skip every task after this one, including anything that cleans up.
    if ($result.FailedCount -gt 0) { throw "$($result.FailedCount) test(s) failed." }

    $covered = [math]::Round($result.CodeCoverage.CoveragePercent, 2)
    Write-Host "    coverage: $covered% (target $CoverageTarget%)"
    if ($covered -lt $CoverageTarget) {
        throw "Coverage $covered% is below the target of $CoverageTarget%."
    }
}

task PreTag Clean, Lint, Build, Test, {
    Import-Module Pester -MinimumVersion 6.0 -ErrorAction Stop

    $manifest = Import-PowerShellDataFile "$script:Source/$ModuleName.psd1"
    Write-Host "    version : $($manifest.ModuleVersion)"

    $config = New-PesterConfiguration
    $config.Run.Path          = "$BuildRoot/tests"
    $config.Run.PassThru      = $true
    $config.Filter.Tag        = 'PreTag'
    $config.Should.DisableV5  = $true
    $config.Output.Verbosity  = 'Detailed'

    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0) { throw "$($result.FailedCount) pre-tag test(s) failed." }
}
