#requires -Version 7.0
<#
.SYNOPSIS
    Regenerates the committed example under examples/.
.DESCRIPTION
    Run from the repository root.

    Two steps, and they are separable on purpose:

      1. Read the live project and write examples/input/claudetesting-graph.json.
         This is the only step that touches the network, and the only one that
         needs a token.
      2. Map that graph onto the producer contract and render it to HTML
         through PSGraphRenderToHtml -> PSGraphRender.

    Step 1 is skipped with -Offline, so anyone can rebuild the HTML from the
    committed graph without a token and without an Azure DevOps account.

    Everything here is READ-ONLY. The module issues GET requests and nothing
    else; no pipeline is queued, run or triggered by any of this.
.PARAMETER Organisation
    Azure DevOps organisation. Defaults to the fixture's.
.PARAMETER Project
    Azure DevOps project. Defaults to the fixture's.
.PARAMETER Offline
    Skip the live read and render from the committed graph JSON.
.EXAMPLE
    pwsh -NoProfile -File examples/Build-Examples.ps1

    Re-reads the project and rebuilds both artifacts. Requires $env:AZDO_PAT.
.EXAMPLE
    pwsh -NoProfile -File examples/Build-Examples.ps1 -Offline

    Rebuilds the HTML from the committed graph. No token, no network.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string] $Organisation = 'jlbalmerjr1',

    [Parameter()]
    [string] $Project = 'ClaudeTesting',

    [Parameter()]
    [switch] $Offline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$examplesRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $examplesRoot
$graphPath = Join-Path $examplesRoot 'input/claudetesting-graph.json'
$htmlPath = Join-Path $examplesRoot 'claudetesting.html'

function Import-Local {
    param([string] $Root, [string] $Name)

    $built = Join-Path $Root "output/$Name/$Name.psd1"
    $source = Join-Path $Root "src/$Name/$Name.psd1"
    $manifest = if (Test-Path -LiteralPath $built) { $built } else { $source }
    if (-not (Test-Path -LiteralPath $manifest)) {
        throw "No $Name manifest found under '$Root'. Run ./build.ps1 there first."
    }
    Import-Module -Name $manifest -Force -ErrorAction Stop
    Get-Module -Name $Name
}

# -- step 1: the live read ---------------------------------------------------
if (-not $Offline) {
    if ([string]::IsNullOrWhiteSpace($env:AZDO_PAT)) {
        throw 'AZDO_PAT is not set. Set $env:AZDO_PAT to a token with Code (Read) and Build (Read), or pass -Offline to rebuild from the committed graph.'
    }

    $null = Import-Local -Root $repoRoot -Name 'PSAzureDevOpsGraph'
    Write-Host "reading $Organisation/$Project (read-only)"

    $graph = Get-AzDoPipelineDependencyGraph -Organisation $Organisation -Project $Project
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $graphPath) -Force
    $graph | Export-AzDoPipelineDependencyGraph -Path $graphPath
    Write-Host ("  wrote input/claudetesting-graph.json ({0} nodes, {1} edges)" -f @($graph.nodes).Count, @($graph.edges).Count)
}

if (-not (Test-Path -LiteralPath $graphPath)) {
    throw "No graph at '$graphPath'. Run without -Offline once to produce it."
}

# -- step 2: map onto the producer contract and render -----------------------
# Import the RENDERER FIRST, then the battery. Order matters and the failure
# it causes is not obvious: importing PSGraphRenderToHtml first makes
# PowerShell satisfy its RequiredModules by auto-loading whatever PSGraphRender
# is on the module path, and importing the sibling copy afterwards leaves TWO
# PSGraphRender module objects loaded. Export-ProducerGraphHtml then resolves
# the backend with `Get-Module -Name PSGraphRender`, gets an array, and builds
# an array of template-set paths - which surfaces much later as
# "Cannot process argument transformation on parameter 'TemplateSetPath'".
$workspace = Split-Path -Parent $repoRoot
foreach ($name in 'PSGraphRender', 'PSGraphRenderToHtml') {
    $sibling = Join-Path $workspace $name
    if (Test-Path -LiteralPath $sibling) { $null = Import-Local -Root $sibling -Name $name }
    else { Import-Module -Name $name -ErrorAction Stop }
}

$loaded = @(Get-Module -Name 'PSGraphRender')
if ($loaded.Count -ne 1) {
    throw "Expected exactly one PSGraphRender module loaded, found $($loaded.Count): $($loaded.Path -join '; ')."
}

$azdo = Get-Content -LiteralPath $graphPath -Raw | ConvertFrom-Json

# This module's graph is its own shape - id/kind/name/repo, from/to/kind - and
# the producer contract wants id/label/type/scope plus parentId for
# containment. The mapping is here, in the example, rather than in the module:
# PSAzureDevOpsGraph does not depend on the render stack and this pass did not
# make it start.
$nodes = foreach ($n in $azdo.nodes) {
    $hasRepo = $n.PSObject.Properties.Name -contains 'repo' -and $n.repo
    $node = [ordered]@{
        id    = [string]$n.id
        label = [string]$n.name
        type  = [string]$n.kind
        scope = if ($hasRepo) { [string]$n.repo } else { $Project }
    }
    # A pipeline or a YAML file is contained by its repository. Containment is
    # parentId and never an edge - a `contains` edge plus a parentId would be
    # two statements of one fact, and the contract refuses the second.
    if ($hasRepo) { $node['parentId'] = "repo:$($n.repo)" }
    else { $node['parentId'] = $null }
    [pscustomobject]$node
}

$nodes = [System.Collections.Generic.List[object]]::new([object[]]$nodes)
$known = @{}
foreach ($n in $nodes) { $known[$n.id] = $true }

# The scan's unresolved references point at targets that are not nodes - that
# is what makes them unresolved. The producer contract requires every edge
# endpoint to resolve, so carrying such an edge means giving its target a node
# rather than discarding the edge.
#
# Discarding was the first thing this script did, and it cost two of the
# fixture's 51 edges. A producer that silently drops what it could not resolve
# reports a graph that looks complete and is not, which is the one outcome both
# contracts are written to prevent.
$invented = 0
foreach ($e in $azdo.edges) {
    $to = [string]$e.to
    if ($known.ContainsKey($to)) { continue }

    $label = if ($to -match '^[a-z]+:(.+)$') { $Matches[1] } else { $to }
    $nodes.Add([pscustomobject][ordered]@{
            id       = $to
            label    = $label
            type     = 'unresolved'
            scope    = $Project
            parentId = $null
        })
    $known[$to] = $true
    $invented++
}
if ($invented) { Write-Host "  carried $invented unresolved reference target(s) as nodes" }

$edges = foreach ($e in $azdo.edges) {
    if (-not $known.ContainsKey([string]$e.from) -or -not $known.ContainsKey([string]$e.to)) { continue }
    $edge = [ordered]@{
        from = [string]$e.from
        to   = [string]$e.to
        kind = [string]$e.kind
    }
    if ([string]$e.kind -eq 'unresolved') {
        $edge['resolved'] = $false
        $edge['reason'] = 'the YAML names a template the scan could not resolve to a file in any repository it read'
    }
    [pscustomobject]$edge
}

$producer = [pscustomobject]@{
    graph = [pscustomobject]@{
        meta  = [pscustomobject]@{
            producer        = 'PSAzureDevOpsGraph'
            producerVersion = [string]$azdo.version
            contractVersion = '0.1.0'
            generatedUtc    = '2026-09-03T00:00:00Z'
            roots           = @("$Organisation/$Project")
        }
        nodes = @($nodes)
        edges = @($edges)
    }
}

$theme = @{
    KindColor         = @{
        pipeline = '#3b7fc4'
        unresolved = '#ff7043'
        yaml     = '#00a884'
        repo     = '#9b8cff'
    }
    KindColorFallback = '#8895a7'
    LinkColor         = @{
        extends            = '#f2c14e'
        pipelineResource   = '#4cc9f0'
        repositoryResource = '#b4536b'
        unresolved         = '#ff7043'
    }
}

$null = Export-ProducerGraphHtml -Graph $producer -OutputPath $htmlPath -Options (
    New-GraphRenderOptions -Layout foundation -Theme $theme `
        -Title "$Project - pipeline dependency graph"
)

Write-Host ("  wrote claudetesting.html ({0:N0} bytes, {1} nodes, {2} edges)" -f
    (Get-Item $htmlPath).Length, @($nodes).Count, @($edges).Count)
Write-Host 'done.'
