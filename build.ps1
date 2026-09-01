#Requires -Version 7.2
<#
.SYNOPSIS
    Entrypoint for the PSAzureDevOpsGraph build.
.DESCRIPTION
    Resolves the dependencies pinned in Requirements.psd1, verifies each against
    every constraint its requirement expresses, then hands off to InvokeBuild.

    Dependencies are resolved, never installed. A build that reaches the gallery
    on its own can change what it is testing between two runs.
.EXAMPLE
    ./build.ps1

    Runs the default task: Clean, Lint, Build, Test.
.EXAMPLE
    ./build.ps1 -Task PreTag

    Runs the pre-tag seals only. PreTag is deliberately not in the default task,
    so a half-finished iteration can still build green.
#>
[CmdletBinding()]
param([string[]] $Task = '.')

$ErrorActionPreference = 'Stop'

function Resolve-BuildDependency {
    <#
    .SYNOPSIS
        Resolve one pinned build dependency and check it against its constraint.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]    $Name,
        [Parameter(Mandatory)] [hashtable] $Requirement
    )

    # Derived from the name, never spelled out. A hard-coded copy per dependency
    # is renamed by hand in four places and the old name survives inside a string.
    $variable = ($Name.ToUpperInvariant() -replace '[^A-Z0-9]', '') + '_MODULE_PATH'
    $override = [Environment]::GetEnvironmentVariable($variable)

    $candidate = $null
    if ($override -and (Test-Path -LiteralPath $override)) {
        $candidate = Get-Item -LiteralPath $override
        $version = [version](Import-PowerShellDataFile -LiteralPath $candidate.FullName -ErrorAction Stop).ModuleVersion
        $resolvedPath = $candidate.FullName
    } else {
        $installed = Get-Module -ListAvailable -Name $Name |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if (-not $installed) {
            throw "$Name was not found. Set `$env:$variable to its manifest, or install $Name."
        }
        $version = $installed.Version
        $resolvedPath = $installed.Path
    }

    # Every constraint the requirement CAN express, not the one written today.
    # A requirement that stops being checked when its shape changes is a
    # requirement nobody is checking.
    foreach ($key in 'RequiredVersion', 'MinimumVersion', 'MaximumVersion') {
        if (-not $Requirement.ContainsKey($key)) { continue }
        $want = [version] $Requirement[$key]
        $ok = switch ($key) {
            'RequiredVersion' { $version -eq $want }
            'MinimumVersion'  { $version -ge $want }
            'MaximumVersion'  { $version -le $want }
        }
        if (-not $ok) {
            throw "$Name resolved to $version at $resolvedPath, which does not satisfy $key = $want."
        }
    }
    if (-not ($Requirement.Keys | Where-Object { $_ -in 'RequiredVersion', 'MinimumVersion', 'MaximumVersion' })) {
        throw "The requirement for $Name states no version constraint. An unpinned build dependency can change what the build is testing between two runs."
    }

    # Out loud, so the fact sits next to the failure rather than three tasks away.
    Write-Host "  ${Name}: $version at $resolvedPath"
    [pscustomobject]@{ Name = $Name; Version = $version; Path = $resolvedPath }
}

Write-Host 'Resolving build dependencies'
$requirements = Import-PowerShellDataFile -LiteralPath "$PSScriptRoot/Requirements.psd1" -ErrorAction Stop
foreach ($name in ($requirements.Keys | Sort-Object)) {
    $resolved = Resolve-BuildDependency -Name $name -Requirement $requirements[$name]
    Import-Module -Name $resolved.Path -Force -ErrorAction Stop
}

try {
    Invoke-Build -Task $Task -File "$PSScriptRoot/PSAzureDevOpsGraph.build.ps1"
    exit 0
} catch {
    Write-Error $_
    exit 1
}
