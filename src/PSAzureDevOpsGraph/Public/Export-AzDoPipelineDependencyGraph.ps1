Set-StrictMode -Version 3.0

function Export-AzDoPipelineDependencyGraph {
    <#
    .SYNOPSIS
        Write a dependency graph as JSON, DOT or HTML.

    .DESCRIPTION
        JSON is the diffable form and the one the functional check compares
        against the oracle. DOT is for Graphviz. HTML is a self-contained page
        that needs no server and no network.

        JSON is written with LF endings and no BOM whatever the platform. Two
        runs of the same project must differ only where the project differs;
        a graph whose diff is dominated by carriage returns is not reviewable.

    .PARAMETER Graph
        A graph from Get-AzDoPipelineDependencyGraph.

    .PARAMETER Path
        File to write. When omitted the rendered text is returned.

    .PARAMETER Format
        Json (default), Dot or Html.

    .EXAMPLE
        Get-AzDoPipelineDependencyGraph -Organisation contoso -Project Platform |
            Export-AzDoPipelineDependencyGraph -Path graph.json

    .EXAMPLE
        $graph | Export-AzDoPipelineDependencyGraph -Format Html -Path graph.html
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [pscustomobject] $Graph,

        [Parameter()][string] $Path,

        [Parameter()]
        [ValidateSet('Json', 'Dot', 'Html')]
        [string] $Format = 'Json'
    )

    process {
        switch ($Format) {
            'Json' { $text = ConvertTo-Json -InputObject $Graph -Depth 12 }
            'Dot'  { $text = ConvertTo-AzDoGraphDot  -Graph $Graph }
            'Html' { $text = ConvertTo-AzDoGraphHtml -Graph $Graph }
        }

        $text = $text -replace "`r`n", "`n"

        if (-not $Path) { return $text }

        if ($PSCmdlet.ShouldProcess($Path, "Write $Format graph")) {
            $directory = Split-Path -Path $Path -Parent
            if ($directory -and -not (Test-Path -LiteralPath $directory)) {
                $null = New-Item -ItemType Directory -Path $directory -Force
            }

            # Resolve relative to the PowerShell location, not the process
            # working directory -- they differ often enough to matter -- but
            # leave an already-rooted path alone.
            $full = if ([System.IO.Path]::IsPathRooted($Path)) { $Path }
                    else { Join-Path (Get-Location).ProviderPath $Path }

            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText(
                [System.IO.Path]::GetFullPath($full),
                ($text.TrimEnd("`n") + "`n"),
                $utf8NoBom)
        }
    }
}

function ConvertTo-AzDoGraphDot {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][pscustomobject] $Graph)

    $shape = @{ pipeline = 'box3d'; yaml = 'note'; repo = 'folder' }

    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine('digraph PSAzureDevOpsGraph {')
    $null = $sb.AppendLine('  rankdir=LR;')
    $null = $sb.AppendLine('  node [fontname="Segoe UI", fontsize=10];')
    $null = $sb.AppendLine('  edge [fontname="Segoe UI", fontsize=8];')
    $null = $sb.AppendLine('')

    foreach ($node in $Graph.nodes) {
        $s = if ($shape.ContainsKey($node.kind)) { $shape[$node.kind] } else { 'ellipse' }
        $null = $sb.AppendLine(('  "{0}" [label="{1}", shape={2}];' -f
            (ConvertTo-AzDoDotString $node.id), (ConvertTo-AzDoDotString $node.name), $s))
    }

    $null = $sb.AppendLine('')

    foreach ($edge in $Graph.edges) {
        $attributes = 'label="{0}"' -f (ConvertTo-AzDoDotString $edge.kind)
        if ($edge.kind -eq 'unresolved') {
            $attributes += ', style=dashed, color="#b00020", fontcolor="#b00020"'
        }
        $null = $sb.AppendLine(('  "{0}" -> "{1}" [{2}];' -f
            (ConvertTo-AzDoDotString $edge.from), (ConvertTo-AzDoDotString $edge.to), $attributes))
    }

    $null = $sb.AppendLine('}')
    return $sb.ToString()
}

function ConvertTo-AzDoDotString {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()] $Text)

    if ($null -eq $Text) { return '' }
    return ([string]$Text).Replace('\', '\\').Replace('"', '\"')
}

function ConvertTo-AzDoGraphHtml {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][pscustomobject] $Graph)

    $e = { param($t) if ($null -eq $t) { '' } else {
        ([string]$t).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') } }

    $unresolved = @($Graph.edges | Where-Object { $_.kind -eq 'unresolved' })

    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine('<!doctype html>')
    $null = $sb.AppendLine('<html lang="en"><head><meta charset="utf-8">')
    $null = $sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    $null = $sb.AppendLine(('<title>Pipeline dependencies &mdash; {0}</title>' -f (& $e $Graph.project)))
    $null = $sb.AppendLine('<style>')
    $null = $sb.AppendLine(@'
:root { color-scheme: light dark; --bg:#fff; --fg:#1a1a1a; --muted:#5b5b5b; --line:#e2e2e2;
        --pipeline:#0a5ca8; --yaml:#3a6b35; --repo:#7a4b9c; --bad:#b00020; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#151515; --fg:#ececec; --muted:#a8a8a8; --line:#333;
          --pipeline:#7fb4e8; --yaml:#9ccf96; --repo:#c9a3e6; --bad:#ff8a9b; }
}
body { background:var(--bg); color:var(--fg); margin:0; padding:2rem 1.25rem;
       font:14px/1.55 "Segoe UI", system-ui, -apple-system, sans-serif; }
main { max-width:70rem; margin:0 auto; }
h1 { font-size:1.4rem; margin:0 0 .25rem; }
h2 { font-size:1.05rem; margin:2rem 0 .5rem; }
.sub { color:var(--muted); margin:0 0 1.5rem; }
table { border-collapse:collapse; width:100%; }
th, td { text-align:left; padding:.4rem .6rem; border-bottom:1px solid var(--line);
         vertical-align:top; }
th { font-weight:600; color:var(--muted); font-size:.8rem; text-transform:uppercase;
     letter-spacing:.04em; }
code { font-family:"Cascadia Code", Consolas, monospace; font-size:.9em; }
.k-pipeline { color:var(--pipeline); } .k-yaml { color:var(--yaml); } .k-repo { color:var(--repo); }
.bad { color:var(--bad); }
.scroll { overflow-x:auto; }
.count { display:inline-block; min-width:1.5rem; }
'@)
    $null = $sb.AppendLine('</style></head><body><main>')

    $null = $sb.AppendLine(('<h1>Pipeline dependencies</h1>'))
    $null = $sb.AppendLine(('<p class="sub">{0} / {1} &mdash; {2} nodes, {3} edges, {4} unresolved</p>' -f
        (& $e $Graph.organisation), (& $e $Graph.project),
        @($Graph.nodes).Count, @($Graph.edges).Count, $unresolved.Count))

    if ($unresolved.Count -gt 0) {
        $null = $sb.AppendLine('<h2 class="bad">Unresolved references</h2>')
        $null = $sb.AppendLine('<div class="scroll"><table><thead><tr><th>From</th><th>Reference</th><th>Kind</th><th>Reason</th></tr></thead><tbody>')
        foreach ($edge in $unresolved) {
            $null = $sb.AppendLine(('<tr><td><code>{0}</code></td><td><code>{1}</code></td><td>{2}</td><td class="bad">{3}</td></tr>' -f
                (& $e $edge.from), (& $e $edge.ref),
                (& $e $(if ($edge.PSObject.Properties.Name -contains 'refKind') { $edge.refKind } else { '' })),
                (& $e $(if ($edge.PSObject.Properties.Name -contains 'reason') { $edge.reason } else { '' }))))
        }
        $null = $sb.AppendLine('</tbody></table></div>')
    }

    $null = $sb.AppendLine('<h2>Nodes</h2>')
    $null = $sb.AppendLine('<div class="scroll"><table><thead><tr><th>Kind</th><th>Id</th><th>Path</th></tr></thead><tbody>')
    foreach ($node in $Graph.nodes) {
        $path = if ($node.PSObject.Properties.Name -contains 'path') { $node.path } else { '' }
        $null = $sb.AppendLine(('<tr><td class="k-{0}">{0}</td><td><code>{1}</code></td><td><code>{2}</code></td></tr>' -f
            (& $e $node.kind), (& $e $node.id), (& $e $path)))
    }
    $null = $sb.AppendLine('</tbody></table></div>')

    $null = $sb.AppendLine('<h2>Edges</h2>')
    $null = $sb.AppendLine('<div class="scroll"><table><thead><tr><th>From</th><th>Kind</th><th>To</th><th>Reference</th></tr></thead><tbody>')
    foreach ($edge in $Graph.edges) {
        $cls = if ($edge.kind -eq 'unresolved') { ' class="bad"' } else { '' }
        $ref = if ($edge.PSObject.Properties.Name -contains 'ref') { $edge.ref } else { '' }
        $null = $sb.AppendLine(('<tr><td><code>{0}</code></td><td{1}>{2}</td><td><code>{3}</code></td><td><code>{4}</code></td></tr>' -f
            (& $e $edge.from), $cls, (& $e $edge.kind), (& $e $edge.to), (& $e $ref)))
    }
    $null = $sb.AppendLine('</tbody></table></div>')

    $null = $sb.AppendLine('</main></body></html>')
    return $sb.ToString()
}
