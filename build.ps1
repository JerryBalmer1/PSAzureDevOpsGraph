#Requires -Version 7.2

<#
.SYNOPSIS
    Entrypoint for the PSAzureDevOpsGraph build.

.DESCRIPTION
    Resolves the dependencies pinned in Requirements.psd1, then hands off to
    InvokeBuild. It resolves rather than installs: a build that reaches the
    gallery on its own can change what it is testing between two runs.

    Exits nonzero when anything fails, because a caller reading $LASTEXITCODE
    is the only consumer that matters.
#>
[CmdletBinding()]
param(
    [string[]] $Task = '.'
)

$ErrorActionPreference = 'Stop'

function Resolve-BuildDependency {
    <#
    .SYNOPSIS
        Finds one pinned build dependency and proves it satisfies its pin.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [hashtable] $Requirement
    )

    $candidates = @(Get-Module -ListAvailable -Name $Name | Sort-Object Version -Descending)
    if (-not $candidates) {
        throw "Missing build dependency '$Name'. Install it and re-run."
    }

    # Every constraint RequiredModules-style requirements can express, not the
    # one that happens to be written today. A requirement that stops being
    # checked when its shape changes is a requirement nobody is checking.
    $matching = $candidates | Where-Object {
        $version = [version] $_.Version
        $ok = $true
        if ($Requirement.ContainsKey('RequiredVersion')) { $ok = $ok -and $version -eq [version] $Requirement['RequiredVersion'] }
        if ($Requirement.ContainsKey('MinimumVersion')) { $ok = $ok -and $version -ge [version] $Requirement['MinimumVersion'] }
        if ($Requirement.ContainsKey('MaximumVersion')) { $ok = $ok -and $version -le [version] $Requirement['MaximumVersion'] }
        $ok
    }

    $resolved = $matching | Select-Object -First 1
    if (-not $resolved) {
        $wanted = ($Requirement.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
        $have = ($candidates.Version -join ', ')
        throw "Build dependency '$Name' does not satisfy $wanted. Available: $have."
    }
    $resolved
}

try {
    $requirements = Import-PowerShellDataFile -LiteralPath "$PSScriptRoot/Requirements.psd1" -ErrorAction Stop
    foreach ($name in ($requirements.Keys | Sort-Object)) {
        $resolved = Resolve-BuildDependency -Name $name -Requirement $requirements[$name]
        # Print the resolved version, so the fact sits next to the failure
        # rather than three tasks away from it.
        Write-Host "  ${name}: $($resolved.Version) at $($resolved.ModuleBase)"
        Import-Module -Name $resolved.Path -Force -ErrorAction Stop
    }

    Invoke-Build -Task $Task -File "$PSScriptRoot/PSAzureDevOpsGraph.build.ps1"
    exit 0
} catch {
    Write-Error $_
    exit 1
}
