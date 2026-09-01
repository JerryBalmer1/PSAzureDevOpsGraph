#Requires -Version 7.2
<#
.SYNOPSIS
    Entrypoint for the PSAzureDevOpsGraph build.
.DESCRIPTION
    Resolves the pinned dependencies in Requirements.psd1, then hands off to
    InvokeBuild. Exits nonzero when anything fails, so a caller reading
    $LASTEXITCODE sees the truth.
#>
[CmdletBinding()]
param([string[]] $Task = '.')

$ErrorActionPreference = 'Stop'

foreach ($name in (Import-PowerShellDataFile "$PSScriptRoot/Requirements.psd1").Keys) {
    if (-not (Get-Module -ListAvailable -Name $name)) {
        throw "Missing dependency '$name'. Install it and re-run."
    }
    Import-Module $name -Force
}

try {
    Invoke-Build -Task $Task -File "$PSScriptRoot/PSAzureDevOpsGraph.build.ps1"
    exit 0
} catch {
    Write-Error $_
    exit 1
}
