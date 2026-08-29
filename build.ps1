#Requires -Version 7.2
<#
    .SYNOPSIS
        Build entrypoint. Resolves pinned dependencies, then runs InvokeBuild.

    .DESCRIPTION
        Dependencies are resolved, never installed silently: a build that
        reaches the gallery on its own can change what it is testing between
        two runs. Exits nonzero when anything fails.
#>
[CmdletBinding()]
param(
    [string[]] $Task = '.'
)

$ErrorActionPreference = 'Stop'

try {
    $requirements = Import-PowerShellDataFile -LiteralPath "$PSScriptRoot/Requirements.psd1"
    foreach ($name in $requirements.Keys) {
        $entry = $requirements[$name]
        $minimum = if ($entry -is [System.Collections.IDictionary]) {
            if ($entry.Contains('RequiredVersion')) { $entry['RequiredVersion'] } else { $entry['MinimumVersion'] }
        }
        else { $entry }

        $module = Get-Module -ListAvailable -Name $name |
            Where-Object { $_.Version -ge [version] $minimum } |
            Sort-Object Version -Descending | Select-Object -First 1

        if (-not $module) {
            throw "Missing dependency '$name' (>= $minimum). Install it and re-run: Install-Module $name -MinimumVersion $minimum -Scope CurrentUser"
        }
        Import-Module $module -Force -ErrorAction Stop
    }

    Invoke-Build -Task $Task -File "$PSScriptRoot/PSAzureDevOpsGraph.build.ps1"
    exit 0
}
catch {
    Write-Error -ErrorRecord $_
    exit 1
}
