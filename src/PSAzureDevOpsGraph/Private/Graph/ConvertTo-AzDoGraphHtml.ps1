function ConvertTo-AzDoGraphHtml {
    <#
    .SYNOPSIS
        Render a dependency graph as a single self-contained HTML page.
    .DESCRIPTION
        Self-contained without qualification: no external script, stylesheet,
        @import, font file, image or http(s) reference of any kind, so the page
        renders from a file:// URL on a machine with no network.

        The layout is computed here rather than by a script in the page. That
        keeps the SVG deterministic and diffable, and it is the only way to
        avoid shipping a layout library the page would have to fetch.

        Unresolved targets are drawn as pseudo-nodes, visibly distinct from real
        ones, and listed again in their own table. They are the answer the tool
        exists to give, and a rendering that drops them is worst exactly where
        it would be most useful.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Graph
    )

    $columnOf = @{ pipeline = 0; yaml = 1; repo = 2 }
    $fill = @{ pipeline = '#dbeafe'; yaml = '#dcfce7'; repo = '#fef3c7' }
    $stroke = @{ pipeline = '#1e40af'; yaml = '#166534'; repo = '#92400e' }
    $edgeColour = [ordered]@{
        definition         = '#1e40af'
        template           = '#166534'
        extends            = '#166534'
        pipelineResource   = '#6b21a8'
        repositoryResource = '#92400e'
        checkout           = '#92400e'
        unresolved         = '#b00020'
    }

    $boxWidth = 300
    $boxHeight = 30
    $gapX = 130
    $gapY = 14
    $marginX = 30
    $marginY = 74

    # Real nodes get a column per kind; unresolved pseudo-nodes get a fourth of
    # their own, so their count is legible without reading any edge.
    $placed = [ordered]@{}
    $rowCount = @(0, 0, 0, 0)

    foreach ($node in $Graph.nodes) {
        $column = $columnOf[[string] $node.kind]
        $placed[$node.id] = [pscustomobject]@{
            Id     = $node.id
            Label  = $node.name
            Kind   = $node.kind
            Ghost  = $false
            Column = $column
            X      = $marginX + $column * ($boxWidth + $gapX)
            Y      = $marginY + $rowCount[$column] * ($boxHeight + $gapY)
        }
        $rowCount[$column]++
    }

    foreach ($edge in $Graph.edges) {
        if ($edge.kind -ne 'unresolved') { continue }
        if ($placed.Contains($edge.to)) { continue }
        $placed[$edge.to] = [pscustomobject]@{
            Id     = $edge.to
            Label  = $edge.to
            Kind   = 'unresolved'
            Ghost  = $true
            Column = 3
            X      = $marginX + 3 * ($boxWidth + $gapX)
            Y      = $marginY + $rowCount[3] * ($boxHeight + $gapY)
        }
        $rowCount[3]++
    }

    $tallest = ($rowCount | Measure-Object -Maximum).Maximum
    $width = $marginX * 2 + 4 * $boxWidth + 3 * $gapX
    $height = $marginY + [math]::Max(1, $tallest) * ($boxHeight + $gapY) + 30

    $svg = [System.Collections.Generic.List[string]]::new()
    $svg.Add('<svg viewBox="0 0 ' + $width + ' ' + $height + '" width="100%" role="img" aria-label="Pipeline dependency graph">')

    $svg.Add('<defs>')
    foreach ($kind in $edgeColour.Keys) {
        $svg.Add('<marker id="arrow-' + $kind + '" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="6" markerHeight="6" orient="auto">' +
            '<path d="M0,0 L8,4 L0,8 z" fill="' + $edgeColour[$kind] + '"/></marker>')
    }
    $svg.Add('</defs>')

    foreach ($edge in $Graph.edges) {
        $from = $placed[$edge.from]
        $to = $placed[$edge.to]
        if (-not $from -or -not $to) { continue }

        $x1 = $from.X + $boxWidth
        $y1 = $from.Y + [int] ($boxHeight / 2)
        $x2 = $to.X
        $y2 = $to.Y + [int] ($boxHeight / 2)
        if ($to.Column -le $from.Column) {
            # A backward or same-column edge leaves and re-enters on the right,
            # so a cycle is visible as a curve rather than as an overlap.
            $x2 = $to.X + $boxWidth
        }
        $mid = [int] (($x1 + $x2) / 2)
        $colour = $edgeColour[[string] $edge.kind]
        $dash = if ($edge.kind -in 'unresolved', 'pipelineResource', 'checkout') { ' stroke-dasharray="5 3"' } else { '' }
        $title = ConvertTo-AzDoHtmlText (Format-AzDoEdgeTitle $edge)

        $svg.Add('<path d="M' + $x1 + ',' + $y1 + ' C' + $mid + ',' + $y1 + ' ' + $mid + ',' + $y2 + ' ' + $x2 + ',' + $y2 +
            '" fill="none" stroke="' + $colour + '" stroke-width="1.5"' + $dash +
            ' marker-end="url(#arrow-' + $edge.kind + ')"><title>' + $title + '</title></path>')
    }

    foreach ($node in $placed.Values) {
        $bg = if ($node.Ghost) { '#ffe4e6' } else { $fill[[string] $node.Kind] }
        $bd = if ($node.Ghost) { '#b00020' } else { $stroke[[string] $node.Kind] }
        $dash = if ($node.Ghost) { ' stroke-dasharray="6 3"' } else { '' }

        $label = [string] $node.Label
        if ($label.Length -gt 44) { $label = $label.Substring(0, 43) + [char] 0x2026 }

        $svg.Add('<g><rect x="' + $node.X + '" y="' + $node.Y + '" width="' + $boxWidth + '" height="' + $boxHeight +
            '" rx="5" fill="' + $bg + '" stroke="' + $bd + '" stroke-width="1.5"' + $dash + '/>' +
            '<text x="' + ($node.X + 10) + '" y="' + ($node.Y + 20) + '" font-size="12">' + (ConvertTo-AzDoHtmlText $label) + '</text>' +
            '<title>' + (ConvertTo-AzDoHtmlText $node.Id) + '</title></g>')
    }

    $headings = @('Pipelines', 'YAML files', 'Repositories', 'Unresolved')
    for ($i = 0; $i -lt 4; $i++) {
        $x = $marginX + $i * ($boxWidth + $gapX)
        $svg.Add('<text x="' + $x + '" y="52" font-size="14" font-weight="600">' +
            (ConvertTo-AzDoHtmlText ($headings[$i] + ' (' + $rowCount[$i] + ')')) + '</text>')
    }
    $svg.Add('</svg>')

    $unresolved = @($Graph.edges | Where-Object { $_.kind -eq 'unresolved' })
    $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($edge in $unresolved) {
        $rows.Add('<tr><td>' + (ConvertTo-AzDoHtmlText $edge.from) + '</td>' +
            '<td><code>' + (ConvertTo-AzDoHtmlText $edge.ref) + '</code></td>' +
            '<td>' + (ConvertTo-AzDoHtmlText $edge.refKind) + '</td>' +
            '<td class="reason">' + (ConvertTo-AzDoHtmlText $edge.reason) + '</td></tr>')
    }
    if ($rows.Count -eq 0) {
        $rows.Add('<tr><td colspan="4">No unresolved references.</td></tr>')
    }

    $generatedBy = if ($Graph.PSObject.Properties['generatedBy']) { [string] $Graph.generatedBy } else { 'PSAzureDevOpsGraph' }
    $subtitlePart = [System.Collections.Generic.List[string]]::new()
    $subtitlePart.Add((ConvertTo-AzDoHtmlText ([string] $Graph.organisation)) + ' / ' + (ConvertTo-AzDoHtmlText ([string] $Graph.project)))
    $subtitlePart.Add('&mdash; ' + @($Graph.nodes).Count + ' nodes, ' + @($Graph.edges).Count + ' edges, ' + $unresolved.Count + ' unresolved.')
    $subtitlePart.Add('Generated by ' + (ConvertTo-AzDoHtmlText $generatedBy) + '.')
    $subtitle = $subtitlePart -join ' '

    $legend = [System.Collections.Generic.List[string]]::new()
    foreach ($kind in $edgeColour.Keys) {
        $legend.Add('<li style="color:' + $edgeColour[$kind] + '">' + $kind + '</li>')
    }

    $page = [System.Collections.Generic.List[string]]::new()
    $page.Add('<!DOCTYPE html>')
    $page.Add('<html lang="en">')
    $page.Add('<head>')
    $page.Add('<meta charset="utf-8">')
    $page.Add('<meta name="viewport" content="width=device-width, initial-scale=1">')
    $page.Add('<title>Pipeline dependency graph - ' + (ConvertTo-AzDoHtmlText ([string] $Graph.project)) + '</title>')
    $page.Add('<style>')
    $page.Add(':root { color-scheme: light; }')
    $page.Add('body { margin: 0; padding: 24px; font-family: "Segoe UI", system-ui, sans-serif; background: #fbfbfd; color: #18181b; }')
    $page.Add('h1 { font-size: 20px; margin: 0 0 4px; }')
    $page.Add('p.sub { margin: 0 0 20px; color: #52525b; font-size: 13px; }')
    $page.Add('section { background: #fff; border: 1px solid #e4e4e7; border-radius: 8px; padding: 16px; margin-bottom: 20px; overflow-x: auto; }')
    $page.Add('h2 { font-size: 15px; margin: 0 0 12px; }')
    $page.Add('table { border-collapse: collapse; width: 100%; font-size: 13px; }')
    $page.Add('th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid #f0f0f2; vertical-align: top; }')
    $page.Add('th { color: #52525b; font-weight: 600; }')
    $page.Add('td.reason { color: #b00020; font-weight: 600; white-space: nowrap; }')
    $page.Add('code { font-family: ui-monospace, Consolas, monospace; font-size: 12px; }')
    $page.Add('ul.legend { list-style: none; display: flex; flex-wrap: wrap; gap: 16px; padding: 0; margin: 0 0 12px; font-size: 12px; }')
    $page.Add('ul.legend li::before { content: ""; display: inline-block; width: 10px; height: 10px; margin-right: 6px; border-radius: 2px; background: currentColor; }')
    $page.Add('</style>')
    $page.Add('</head>')
    $page.Add('<body>')
    $page.Add('<h1>Pipeline dependency graph</h1>')
    $page.Add('<p class="sub">' + $subtitle + '</p>')
    $page.Add('<section>')
    $page.Add('<h2>Graph</h2>')
    $page.Add('<ul class="legend">' + ($legend -join '') + '</ul>')
    $page.Add($svg -join [Environment]::NewLine)
    $page.Add('</section>')
    $page.Add('<section>')
    $page.Add('<h2>Unresolved references (' + $unresolved.Count + ')</h2>')
    $page.Add('<table><thead><tr><th>From</th><th>Reference</th><th>Kind</th><th>Reason</th></tr></thead><tbody>')
    $page.Add($rows -join [Environment]::NewLine)
    $page.Add('</tbody></table>')
    $page.Add('</section>')
    $page.Add('</body>')
    $page.Add('</html>')

    $page -join [Environment]::NewLine
}
