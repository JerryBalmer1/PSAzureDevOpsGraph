#Requires -Version 7.2
<#
.SYNOPSIS
    Build entrypoint for PSAzureDevOpsGraph.
.DESCRIPTION
    A bootstrap, not a second build system. The tasks live in
    PSAzureDevOpsGraph.build.ps1; this file exists so that someone who has just
    cloned the repository can type ./build.ps1 without first knowing that the
    build uses Invoke-Build, and so that CI has one command to call.

    Build dependencies are pinned in Requirements.psd1 and nowhere else.
.EXAMPLE
    ./build.ps1
.EXAMPLE
    ./build.ps1 -Task PreTag
#>
[CmdletBinding()]
param(
    # Any task in PSAzureDevOpsGraph.build.ps1. '.' is Clean, Lint, Build, Test.
    [string[]]$Task = '.',

    # Install missing build dependencies for the current user.
    [switch]$Bootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$requirements = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'Requirements.psd1')

foreach ($name in $requirements.Keys) {
    $wanted = [version]$requirements[$name]
    $have   = Get-Module -ListAvailable -Name $name |
        Where-Object { $_.Version -ge $wanted } | Select-Object -First 1
    if ($have) { continue }

    if (-not $Bootstrap) {
        throw "$name $wanted or later is required and is not installed. Run ./build.ps1 -Bootstrap, or install it yourself: Install-Module $name -MinimumVersion $wanted -Scope CurrentUser"
    }
    Write-Host "==> installing $name $wanted"
    Install-Module -Name $name -MinimumVersion $wanted -Scope CurrentUser -Force -AllowClobber
}

Import-Module InvokeBuild -MinimumVersion $requirements.InvokeBuild -ErrorAction Stop
Invoke-Build -Task $Task -File (Join-Path $PSScriptRoot 'PSAzureDevOpsGraph.build.ps1')
