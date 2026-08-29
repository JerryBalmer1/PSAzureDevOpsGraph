#requires -Version 5.1
<#
.SYNOPSIS
    Build and test PSAzureDevOpsGraph.

.DESCRIPTION
    Tasks:

        Clean     remove output/ and testResults/
        Build     compose the module into output/PSAzureDevOpsGraph/
        Analyze   PSScriptAnalyzer over src/ and tests/, if it is installed
        Test      Pester over tests/, results into testResults/
        All       Clean, Build, Analyze, Test   (the default)

    The build is a copy rather than a concatenation: the module already loads
    by dot-sourcing Public/ and Private/, so composing it any other way would
    mean the shipped module and the tested module are different artifacts.

    Exits non-zero on failure so that a caller can rely on the exit code.

.PARAMETER Task
    Which task to run. Defaults to All.

.PARAMETER TestName
    Run only tests whose full name matches this.

.EXAMPLE
    ./build.ps1

.EXAMPLE
    ./build.ps1 -Task Test
#>
[CmdletBinding()]
param(
    [ValidateSet('Clean', 'Build', 'Analyze', 'Test', 'All')]
    [string] $Task = 'All',

    [string] $TestName
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root        = $PSScriptRoot
$moduleName  = 'PSAzureDevOpsGraph'
$sourceDir   = Join-Path $root 'src' $moduleName
$outputDir   = Join-Path $root 'output'
$stageDir    = Join-Path $outputDir $moduleName
$testDir     = Join-Path $root 'tests'
$resultsDir  = Join-Path $root 'testResults'

function Write-Step {
    param([string] $Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Clean {
    Write-Step 'Clean'
    foreach ($dir in $outputDir, $resultsDir) {
        if (Test-Path -LiteralPath $dir) {
            Remove-Item -LiteralPath $dir -Recurse -Force
            Write-Host "    removed $dir"
        }
    }
}

function Invoke-Build {
    Write-Step 'Build'

    if (-not (Test-Path -LiteralPath $sourceDir)) { throw "No module source at $sourceDir" }

    $null = New-Item -ItemType Directory -Path $stageDir -Force
    Copy-Item -Path (Join-Path $sourceDir '*') -Destination $stageDir -Recurse -Force

    $manifest = Join-Path $stageDir "$moduleName.psd1"
    $null = Test-ModuleManifest -Path $manifest -ErrorAction Stop

    # A module that parses only when imported fails far from the cause. Parse
    # every file here, where the error still names the file.
    $errors = $null
    foreach ($file in Get-ChildItem -Path $stageDir -Recurse -Filter '*.ps1' -File) {
        $tokens = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
                    $file.FullName, [ref]$tokens, [ref]$errors)
        if ($errors) { throw "Parse error in $($file.Name): $($errors[0].Message)" }
    }

    $count = @(Get-ChildItem -Path $stageDir -Recurse -File).Count
    Write-Host "    staged $count files into $stageDir"
}

function Invoke-Analyze {
    Write-Step 'Analyze'

    if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
        Write-Host '    PSScriptAnalyzer not installed; skipped' -ForegroundColor Yellow
        return
    }

    Import-Module PSScriptAnalyzer -ErrorAction Stop
    $findings = @(Invoke-ScriptAnalyzer -Path $sourceDir -Recurse -Severity Error, Warning)
    $findings += @(Invoke-ScriptAnalyzer -Path $testDir -Recurse -Severity Error)

    if ($findings.Count -eq 0) {
        Write-Host '    clean'
        return
    }

    $findings | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize | Out-String | Write-Host
    if (@($findings | Where-Object Severity -eq 'Error').Count -gt 0) {
        throw "PSScriptAnalyzer reported $($findings.Count) issue(s), including errors"
    }
    Write-Host "    $($findings.Count) warning(s)" -ForegroundColor Yellow
}

function Invoke-Test {
    Write-Step 'Test'

    if (-not (Get-Module -ListAvailable Pester | Where-Object Version -ge ([version]'5.0'))) {
        throw 'Pester 5 or later is required. Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser'
    }

    Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
    $null = New-Item -ItemType Directory -Path $resultsDir -Force

    $config = New-PesterConfiguration
    $config.Run.Path        = $testDir
    $config.Run.PassThru    = $true
    $config.Output.Verbosity= 'Detailed'
    $config.TestResult.Enabled      = $true
    $config.TestResult.OutputPath   = Join-Path $resultsDir 'pester.xml'
    $config.TestResult.OutputFormat = 'NUnitXml'

    if ($TestName) { $config.Filter.FullName = $TestName }

    $result = Invoke-Pester -Configuration $config

    Write-Host ''
    Write-Host ("    passed {0}  failed {1}  skipped {2}" -f
        $result.PassedCount, $result.FailedCount, $result.SkippedCount)

    if ($result.FailedCount -gt 0) { throw "$($result.FailedCount) test(s) failed" }
}

try {
    switch ($Task) {
        'Clean'   { Invoke-Clean }
        'Build'   { Invoke-Build }
        'Analyze' { Invoke-Analyze }
        'Test'    { Invoke-Test }
        'All'     { Invoke-Clean; Invoke-Build; Invoke-Analyze; Invoke-Test }
    }

    Write-Host ''
    Write-Host "Build succeeded ($Task)." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ''
    Write-Host "Build failed ($Task): $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    exit 1
}
