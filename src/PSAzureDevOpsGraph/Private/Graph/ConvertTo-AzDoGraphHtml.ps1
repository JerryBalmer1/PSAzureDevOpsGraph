function ConvertTo-AzDoGraphHtml {
    <#
    .SYNOPSIS
        Renders a dependency graph as one self-contained HTML page.
    .DESCRIPTION
        Self-contained without qualification: no external script, stylesheet,
        @import, or http(s) reference of any kind, so it renders from a file://
        URL with no network. The diagram is inline SVG laid out deterministically
        in columns by node kind, so two runs of the same project produce the same
        page.

        Unresolved targets are drawn as dashed pseudo-nodes in their own column.
        They are the answer the tool exists to give.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [psobject] $Graph
    )

    function Get-Escaped {
        param([AllowNull()] [string] $Text)
        if ($null -eq $Text) { return '' }
        $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
    }

    $real = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($node in $Graph.nodes) { $null = $real.Add($node.id) }

    # Pseudo-nodes, in first-appearance order, so the layout is stable.
    $pseudo = [System.Collections.Generic.List[string]]::new()
    foreach ($edge in $Graph.edges) {
        if (-not $real.Contains($edge.to) -and -not $pseudo.Contains($edge.to)) { $pseudo.Add($edge.to) }
    }

    $columns = [ordered] @{
        pipeline = @($Graph.nodes | Where-Object { $_.kind -eq 'pipeline' })
        yaml     = @($Graph.nodes | Where-Object { $_.kind -eq 'yaml' })
        repo     = @($Graph.nodes | Where-Object { $_.kind -eq 'repo' })
    }

    $columnX = @{ pipeline = 140; yaml = 560; repo = 980; unresolved = 1320 }
    $rowHeight = 34
    $position = @{}

    foreach ($kind in $columns.Keys) {
        $row = 0
        foreach ($node in $columns[$kind]) {
            $position[$node.id] = @{ X = $columnX[$kind]; Y = 60 + ($row * $rowHeight) }
            $row++
        }
    }
    $row = 0
    foreach ($id in $pseudo) {
        $position[$id] = @{ X = $columnX['unresolved']; Y = 60 + ($row * $rowHeight) }
        $row++
    }

    $height = 120 + ($rowHeight * ([Math]::Max(
                [Math]::Max($columns['pipeline'].Count, $columns['yaml'].Count),
                [Math]::Max($columns['repo'].Count, $pseudo.Count))))
    $width = 1600

    $svg = [System.Collections.Generic.List[string]]::new()
    $svg.Add("<svg viewBox=`"0 0 $width $height`" width=`"100%`" role=`"img`" aria-label=`"Pipeline dependency graph`">")
    $svg.Add('<defs><marker id="arrow" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="#7a8899"/></marker></defs>')

    foreach ($edge in $Graph.edges) {
        $from = $position[$edge.from]
        $to = $position[$edge.to]
        if (-not $from -or -not $to) { continue }
        $unresolved = $edge.kind -eq 'unresolved'
        $stroke = if ($unresolved) { '#b3261e' } else { '#7a8899' }
        $dash = if ($unresolved) { ' stroke-dasharray="5 4"' } else { '' }
        $midX = [int] (($from.X + $to.X) / 2)
        $svg.Add("<path d=`"M $($from.X + 4) $($from.Y) C $midX $($from.Y), $midX $($to.Y), $($to.X - 8) $($to.Y)`" fill=`"none`" stroke=`"$stroke`" stroke-width=`"1.2`"$dash marker-end=`"url(#arrow)`"><title>$(Get-Escaped "$($edge.from) -> $($edge.to) [$($edge.kind)]")</title></path>")
    }

    foreach ($kind in $columns.Keys) {
        foreach ($node in $columns[$kind]) {
            $p = $position[$node.id]
            $svg.Add("<circle cx=`"$($p.X)`" cy=`"$($p.Y)`" r=`"5`" fill=`"#1f6feb`"/>")
            $svg.Add("<text x=`"$($p.X + 10)`" y=`"$($p.Y + 4)`" font-size=`"11`" fill=`"#0b1a2b`">$(Get-Escaped $node.name)<title>$(Get-Escaped $node.id)</title></text>")
        }
    }
    foreach ($id in $pseudo) {
        $p = $position[$id]
        $svg.Add("<circle cx=`"$($p.X)`" cy=`"$($p.Y)`" r=`"5`" fill=`"none`" stroke=`"#b3261e`" stroke-width=`"1.5`" stroke-dasharray=`"3 2`"/>")
        $svg.Add("<text x=`"$($p.X + 10)`" y=`"$($p.Y + 4)`" font-size=`"11`" fill=`"#b3261e`">$(Get-Escaped $id)</text>")
    }
    $svg.Add('</svg>')

    $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($edge in $Graph.edges) {
        $class = if ($edge.kind -eq 'unresolved') { ' class="unresolved"' } else { '' }
        $refText = if ($edge.PSObject.Properties['ref']) { $edge.ref } else { '' }
        $reasonText = if ($edge.PSObject.Properties['reason']) { $edge.reason } else { '' }
        $rows.Add("<tr$class><td>$(Get-Escaped $edge.from)</td><td>$(Get-Escaped $edge.to)</td><td>$(Get-Escaped $edge.kind)</td><td>$(Get-Escaped $refText)</td><td>$(Get-Escaped $reasonText)</td></tr>")
    }

    $unresolvedCount = @($Graph.edges | Where-Object { $_.kind -eq 'unresolved' }).Count

    @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Pipeline dependency graph - $(Get-Escaped $Graph.organisation)/$(Get-Escaped $Graph.project)</title>
<style>
:root { color-scheme: light dark; }
body { margin: 0; padding: 24px; font: 14px/1.5 "Segoe UI", system-ui, sans-serif; background: #ffffff; color: #0b1a2b; }
h1 { font-size: 20px; margin: 0 0 4px; }
p.meta { margin: 0 0 20px; color: #52657a; }
figure { margin: 0 0 28px; overflow-x: auto; border: 1px solid #d9e0e8; border-radius: 6px; padding: 8px; }
table { border-collapse: collapse; width: 100%; font-size: 12px; }
th, td { text-align: left; padding: 5px 8px; border-bottom: 1px solid #e6ebf1; vertical-align: top; }
th { background: #f4f7fa; font-weight: 600; }
tr.unresolved td { color: #b3261e; }
.legend span { display: inline-block; margin-right: 16px; color: #52657a; font-size: 12px; }
</style>
</head>
<body>
<h1>Pipeline dependency graph</h1>
<p class="meta">$(Get-Escaped $Graph.organisation) / $(Get-Escaped $Graph.project) &mdash; $($Graph.nodes.Count) nodes, $($Graph.edges.Count) edges, $unresolvedCount unresolved</p>
<p class="legend"><span>&#9679; pipeline, yaml and repo nodes, left to right</span><span style="color:#b3261e">&#9675; unresolved target</span></p>
<figure>
$($svg -join "`n")
</figure>
<table>
<thead><tr><th>From</th><th>To</th><th>Kind</th><th>Reference</th><th>Reason</th></tr></thead>
<tbody>
$($rows -join "`n")
</tbody>
</table>
</body>
</html>
"@
}
