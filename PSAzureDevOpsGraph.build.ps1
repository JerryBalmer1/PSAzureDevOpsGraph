#Requires -Version 7.2
<#
    InvokeBuild tasks for PSAzureDevOpsGraph.

    Clean, Lint, Build, Test are the default. PreTag is declared but deliberately
    NOT in the default list, so a half-finished iteration can still build green.
#>

$script:ModuleName = 'PSAzureDevOpsGraph'
$script:SourceDir = "$BuildRoot/src/$script:ModuleName"
$script:OutputDir = "$BuildRoot/output/$script:ModuleName"
$script:Manifest = "$script:SourceDir/$script:ModuleName.psd1"

# Coverage target, declared once. The Test task reads the number back off the
# Pester result rather than keeping a second copy here; two thresholds in two
# places drift, and the drift is silent because both halves keep working.
$script:CoverageTarget = 70

function Resolve-BuildDependency {
    <#
    .SYNOPSIS
        Resolve a runtime dependency and check the resolved version against what
        the manifest actually requires.
    #>
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $ManifestPath
    )

    # The environment variable is derived from the name, never spelled out, so a
    # copy-and-rename cannot leave the old name hiding inside a string.
    $variable = ($Name.ToUpperInvariant() -replace '[^A-Z0-9]', '') + '_MODULE_PATH'
    $override = [Environment]::GetEnvironmentVariable($variable)

    $resolved = $null
    foreach ($candidate in @(
            $override
            (Join-Path (Split-Path -Parent $BuildRoot) "$Name/output/$Name/$Name.psd1")
            (Join-Path (Split-Path -Parent $BuildRoot) "$Name/src/$Name/$Name.psd1"))) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { $resolved = $candidate; break }
    }
    if (-not $resolved) {
        $installed = Get-Module -ListAvailable -Name $Name |
            Sort-Object Version -Descending | Select-Object -First 1
        if ($installed) { $resolved = $installed.Path }
    }
    if (-not $resolved) {
        throw "$Name was not found. Set $variable, check out $Name beside this repository, or install it."
    }

    $found = [version](Import-PowerShellDataFile -LiteralPath $resolved -ErrorAction Stop).ModuleVersion

    $declared = @((Import-PowerShellDataFile -LiteralPath $ManifestPath -ErrorAction Stop).RequiredModules |
        Where-Object { $_ -is [System.Collections.IDictionary] -and $_['ModuleName'] -eq $Name })
    if ($declared.Count -ne 1) {
        throw "The manifest declares $($declared.Count) RequiredModules entries for '$Name'. The version this build resolved cannot be checked against a requirement that is not there."
    }

    # Every constraint RequiredModules CAN express, not the one written today. A
    # requirement that stops being checked when its shape changes is a
    # requirement nobody is checking.
    $requirement = $declared[0]
    foreach ($key in 'RequiredVersion', 'ModuleVersion', 'MaximumVersion') {
        if (-not $requirement.Contains($key)) { continue }
        $want = [version] $requirement[$key]
        switch ($key) {
            'RequiredVersion' { if ($found -ne $want) { throw "$Name resolved to $found at $resolved but the manifest requires exactly $want." } }
            'ModuleVersion' { if ($found -lt $want) { throw "$Name resolved to $found at $resolved but the manifest requires at least $want." } }
            'MaximumVersion' { if ($found -gt $want) { throw "$Name resolved to $found at $resolved but the manifest allows at most $want." } }
        }
    }

    # RETURNS the facts; it does not print them. A function that both writes a
    # message and returns a value puts both in the output stream, and the
    # caller's "$null = ..." then swallows the message along with the value --
    # so the resolved version silently stops being printed while the build still
    # passes. The caller prints.
    [pscustomobject]@{ Name = $Name; Version = $found; Path = $resolved }
}

task Clean {
    if (Test-Path -LiteralPath "$BuildRoot/output") {
        Remove-Item -LiteralPath "$BuildRoot/output" -Recurse -Force
    }
    Write-Build Green 'Removed output/.'
}

task Lint {
    $findings = Invoke-ScriptAnalyzer -Path "$BuildRoot/src" -Recurse -Settings "$BuildRoot/PSScriptAnalyzerSettings.psd1"
    if ($findings) {
        $findings | Format-Table -AutoSize | Out-String | Write-Host
        throw "PSScriptAnalyzer reported $($findings.Count) finding(s)."
    }
    Write-Build Green 'PSScriptAnalyzer: 0 findings.'
}

task Resolve {
    Write-Build Gray 'Runtime dependencies:'
    $dependency = Resolve-BuildDependency -Name 'powershell-yaml' -ManifestPath $script:Manifest
    # Printed out loud, so the version actually used sits next to any failure
    # rather than three tasks away from it. RequiredModules with ModuleVersion is
    # a FLOOR, so the version tested against and the version used are two facts.
    Write-Build Green "  $($dependency.Name): $($dependency.Version) at $($dependency.Path)"
}

task Build Resolve, {
    $null = New-Item -ItemType Directory -Path $script:OutputDir -Force

    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine('# This file is auto-generated by the build. Do not edit.')
    $null = $sb.AppendLine('#')
    $null = $sb.AppendLine('# Private/** then Public/*, concatenated. Under concatenation $PSScriptRoot')
    $null = $sb.AppendLine('# names the generated file directory, so assets resolve from')
    $null = $sb.AppendLine('# $script:ModuleRoot, which the dev loader sets to the same place.')
    $null = $sb.AppendLine('$script:ModuleRoot = $PSScriptRoot')
    $null = $sb.AppendLine('')

    # Private recursively and sorted by full path, so ordering is stable across
    # subfolders; then Public. A public function may call a private one at load
    # time, which is why the order is not the other way round.
    $private = @(Get-ChildItem -LiteralPath "$script:SourceDir/Private" -Filter *.ps1 -Recurse -File |
        Sort-Object FullName)
    $public = @(Get-ChildItem -LiteralPath "$script:SourceDir/Public" -Filter *.ps1 -File |
        Sort-Object Name)

    foreach ($file in $private + $public) {
        $null = $sb.AppendLine("# --- $($file.Name) ---")
        $null = $sb.AppendLine((Get-Content -LiteralPath $file.FullName -Raw))
        $null = $sb.AppendLine('')
    }

    # Emitted as a real call listing every name as a string constant. A
    # commented-out line here is the cheapest mistake in the build to make.
    $names = $public.BaseName
    $quoted = ($names | ForEach-Object { "'$_'" }) -join ', '
    $null = $sb.AppendLine("Export-ModuleMember -Function $quoted")

    Set-Content -LiteralPath "$script:OutputDir/$script:ModuleName.psm1" -Value $sb.ToString() -Encoding utf8NoBOM
    Copy-Item -LiteralPath $script:Manifest -Destination "$script:OutputDir/$script:ModuleName.psd1" -Force

    # Culture directories must be copied or Get-Help finds no about_ topic. This
    # is the most commonly missed step, because everything else works without it.
    foreach ($culture in Get-ChildItem -LiteralPath $script:SourceDir -Directory |
        Where-Object { $_.Name -match '^[a-z]{2}(-[A-Za-z]{2,4})?$' }) {
        Copy-Item -LiteralPath $culture.FullName -Destination $script:OutputDir -Recurse -Force
        Write-Build Green "  copied culture directory $($culture.Name)/"
    }

    Write-Build Green "Built $($private.Count) private + $($public.Count) public into output/$script:ModuleName/."
}

task Test Build, {
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = "$BuildRoot/tests"
    $cfg.Run.Throw = $true                      # NOT Run.Exit - that kills the host process.
    # PassThru, or Invoke-Pester returns NOTHING and every gate written against
    # the result silently cannot fire: $percent reads 0, $target reads $null,
    # and "0 -lt $null" is false, so the coverage throw below is unreachable
    # while looking exactly like a working gate.
    $cfg.Run.PassThru = $true
    $cfg.Run.FailOnNullOrEmptyForEach = $false  # An empty -ForEach is inapplicable, not fatal.
    $cfg.Should.DisableV5 = $true
    $cfg.Filter.ExcludeTag = 'PreTag'
    $cfg.Output.Verbosity = 'Normal'
    $cfg.CodeCoverage.Enabled = $true
    $cfg.CodeCoverage.Path = "$script:OutputDir/$script:ModuleName.psm1"
    $cfg.CodeCoverage.CoveragePercentTarget = $script:CoverageTarget

    $result = Invoke-Pester -Configuration $cfg

    # Read the target back off the result rather than keeping a second copy of
    # the number here.
    $coverage = $result.CodeCoverage
    $percent = [math]::Round($coverage.CoveragePercent, 2)
    $target = $coverage.CoveragePercentTarget
    if ($percent -lt $target) {
        throw "Line coverage $percent% is below the target of $target%. Raise coverage, or lower the target deliberately and say so."
    }
    Write-Build Green "Line coverage: $percent% (target $target%)"
}

task PreTag Build, {
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = "$BuildRoot/tests"
    $cfg.Run.Throw = $true
    $cfg.Run.PassThru = $true    # Without it the guard below reads $null and always throws.
    $cfg.Should.DisableV5 = $true
    $cfg.Filter.Tag = 'PreTag'
    $result = Invoke-Pester -Configuration $cfg

    # Count what RAN. Discovery walks the whole tests path before the tag filter
    # applies, so TotalCount is never zero and a guard written against it can
    # never fire.
    if (($result.PassedCount + $result.FailedCount) -eq 0) {
        throw 'The PreTag filter selected no test at all. A gate that grades nothing is not a gate.'
    }
    Write-Build Green "PreTag: $($result.PassedCount) passed."
}

task . Clean, Lint, Build, Test
