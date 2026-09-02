#Requires -Version 7.2
<#
.SYNOPSIS
    Build, analyse and test PSAzureDevOpsGraph.
.DESCRIPTION
    Stages the module into output/ and runs the test suite. No network and no
    credentials are required: the tests that need Azure DevOps are tagged
    Integration and are excluded unless -IncludeIntegration is given.
#>
[CmdletBinding()]
param(
    [ValidateSet('Clean', 'Build', 'Test', 'All')]
    [string]$Task = 'All',
    [switch]$IncludeIntegration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root       = $PSScriptRoot
$moduleName = 'PSAzureDevOpsGraph'
$source     = Join-Path $root 'src' $moduleName
$outputRoot = Join-Path $root 'output'
$staged     = Join-Path $outputRoot $moduleName
$results    = Join-Path $root 'testResults'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }

function Invoke-Clean {
    Write-Step 'Clean'
    foreach ($p in $outputRoot, $results) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
    }
}

function Invoke-Build {
    Write-Step 'Build'
    $null = New-Item -ItemType Directory -Path $staged -Force
    Copy-Item -Path (Join-Path $source '*') -Destination $staged -Recurse -Force

    $manifest = Join-Path $staged "$moduleName.psd1"
    $null = Test-ModuleManifest -Path $manifest
    Write-Host "    staged  : $staged"
    Write-Host "    manifest: OK"

    $parseErrors = @()
    foreach ($file in Get-ChildItem -LiteralPath $staged -Filter '*.ps1' -Recurse -File) {
        $tokens = $null; $errs = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errs)
        if ($errs) { $parseErrors += $errs | ForEach-Object { "$($file.Name):$($_.Extent.StartLineNumber) $($_.Message)" } }
    }
    if ($parseErrors) { throw "Parse errors:`n$($parseErrors -join "`n")" }
    Write-Host "    parse   : OK"
}

function Invoke-Test {
    Write-Step 'Test'
    if (-not (Get-Module -ListAvailable -Name Pester | Where-Object Version -ge '5.0')) {
        throw 'Pester 5+ is required.'
    }
    Import-Module Pester -MinimumVersion 5.0 -Force
    $null = New-Item -ItemType Directory -Path $results -Force

    $config = New-PesterConfiguration
    $config.Run.Path      = Join-Path $root 'tests'
    $config.Run.PassThru  = $true
    $config.Output.Verbosity = 'Detailed'
    $config.TestResult.Enabled      = $true
    $config.TestResult.OutputPath   = Join-Path $results 'pester.xml'
    if (-not $IncludeIntegration) { $config.Filter.ExcludeTag = 'Integration' }

    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0) { throw "$($result.FailedCount) test(s) failed." }
    Write-Host "    passed  : $($result.PassedCount)  skipped: $($result.SkippedCount)"
}

switch ($Task) {
    'Clean' { Invoke-Clean }
    'Build' { Invoke-Build }
    'Test'  { Invoke-Test }
    'All'   { Invoke-Clean; Invoke-Build; Invoke-Test }
}

Write-Step 'Done'
