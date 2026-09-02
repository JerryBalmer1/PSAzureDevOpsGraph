function Export-AzDoPipelineDependencyGraph {
    <#
    .SYNOPSIS
        Exports a dependency graph as JSON, DOT or HTML.
    .DESCRIPTION
        JSON is the diffable form and is the one the functional check compares:
        it is emitted with stable ordering and no machine-specific content so
        that two runs of the same project produce identical bytes.

        DOT and HTML are the readable forms. The HTML is a single self-contained
        file with no external references, because the usual reason to want one is
        to attach it to a work item or mail it to somebody who will open it on a
        machine that cannot reach a CDN.
    .EXAMPLE
        Get-AzDoPipelineDependencyGraph -Organisation o -Project p |
            Export-AzDoPipelineDependencyGraph -Format Json -Path graph.json
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Graph,

        [ValidateSet('Json', 'Dot', 'Html')]
        [string]$Format = 'Json',

        # Omit to return the rendered text instead of writing a file.
        [string]$Path
    )

    process {
        $text = switch ($Format) {
            'Json' {
                $ordered = [ordered]@{
                    version      = $Graph.version
                    organisation = $Graph.organisation
                    project      = $Graph.project
                }
                if ($Graph.PSObject.Properties['generatedBy'] -and $Graph.generatedBy) {
                    $ordered['generatedBy'] = $Graph.generatedBy
                }
                $ordered['nodes'] = @($Graph.nodes)
                $ordered['edges'] = @($Graph.edges)
                ($ordered | ConvertTo-Json -Depth 12)
            }

            'Dot' {
                $shape = @{ pipeline = 'box'; yaml = 'note'; repo = 'folder' }
                $lines = [System.Collections.Generic.List[string]]::new()
                $lines.Add('digraph PipelineDependencies {')
                $lines.Add('    rankdir=LR;')
                $lines.Add('    node [fontname="Segoe UI", fontsize=10];')
                $lines.Add('    edge [fontname="Segoe UI", fontsize=8];')
                foreach ($node in $Graph.nodes) {
                    $lines.Add(('    "{0}" [label="{1}", shape={2}];' -f $node.id, ($node.name -replace '"', '\"'), $shape[[string]$node.kind]))
                }
                foreach ($edge in $Graph.edges) {
                    $style = if ($edge.kind -eq 'unresolved') { ', style=dashed, color=red' } else { '' }
                    $lines.Add(('    "{0}" -> "{1}" [label="{2}"{3}];' -f $edge.from, $edge.to, $edge.kind, $style))
                }
                $lines.Add('}')
                $lines -join "`n"
            }

            'Html' {
                $json = @{
                    nodes = @($Graph.nodes)
                    edges = @($Graph.edges)
                } | ConvertTo-Json -Depth 12 -Compress
                # Escape '&' first, or the entities produced below get re-escaped.
                $encoded = $json -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
                $unresolved = @($Graph.edges | Where-Object { $_.kind -eq 'unresolved' }).Count
                $title = "$($Graph.organisation) / $($Graph.project) pipeline dependencies"
                @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>$title</title>
<style>
:root { color-scheme: light dark; }
body { font: 14px/1.5 "Segoe UI", system-ui, sans-serif; margin: 0; padding: 2rem; }
h1 { font-size: 1.25rem; margin: 0 0 .25rem; }
p.meta { color: #666; margin: 0 0 1.5rem; }
table { border-collapse: collapse; width: 100%; margin-bottom: 2rem; }
th, td { text-align: left; padding: .35rem .6rem; border-bottom: 1px solid #8884; vertical-align: top; }
th { font-weight: 600; white-space: nowrap; }
code { font-family: Consolas, ui-monospace, monospace; font-size: .9em; }
tr.unresolved td { color: #b00; }
.kind { display: inline-block; padding: 0 .4rem; border: 1px solid #8886; border-radius: 3px; font-size: .8em; }
</style>
</head>
<body>
<h1>$title</h1>
<p class="meta">$($Graph.nodes.Count) nodes, $($Graph.edges.Count) edges, $unresolved unresolved.</p>

<h2>Nodes</h2>
<table><thead><tr><th>Id</th><th>Kind</th><th>Name</th><th>Repository</th><th>Path</th></tr></thead><tbody>
$(($Graph.nodes | ForEach-Object {
    $repo = if ($_.Contains('repo')) { $_.repo } else { '' }
    $p    = if ($_.Contains('path')) { $_.path } else { '' }
    "<tr><td><code>$($_.id)</code></td><td><span class=`"kind`">$($_.kind)</span></td><td>$($_.name)</td><td>$repo</td><td><code>$p</code></td></tr>"
}) -join "`n")
</tbody></table>

<h2>Edges</h2>
<table><thead><tr><th>From</th><th>To</th><th>Kind</th><th>Reference</th><th>Reason</th></tr></thead><tbody>
$(($Graph.edges | ForEach-Object {
    $cls    = if ($_.kind -eq 'unresolved') { ' class="unresolved"' } else { '' }
    $ref    = if ($_.Contains('ref')) { $_.ref } else { '' }
    $reason = if ($_.Contains('reason')) { $_.reason } else { '' }
    "<tr$cls><td><code>$($_.from)</code></td><td><code>$($_.to)</code></td><td><span class=`"kind`">$($_.kind)</span></td><td><code>$ref</code></td><td>$reason</td></tr>"
}) -join "`n")
</tbody></table>

<script id="graph-data" type="application/json">$encoded</script>
</body>
</html>
"@
            }
        }

        if ($Path) {
            # Resolve against the session's location, not the process working
            # directory, which PowerShell does not keep in step with Set-Location.
            # An already-rooted path is taken as given: joining it to the current
            # location would produce 'C:\here\C:\there'.
            $full = if ([System.IO.Path]::IsPathRooted($Path)) { $Path }
                    else { Join-Path (Get-Location).ProviderPath $Path }
            $full = [System.IO.Path]::GetFullPath($full)

            $directory = Split-Path -Parent $full
            if ($directory -and -not (Test-Path -LiteralPath $directory)) {
                $null = New-Item -ItemType Directory -Path $directory -Force
            }

            # UTF-8 without BOM and LF endings: the JSON is committed and diffed.
            $content = $text -replace "`r`n", "`n"
            if ($Format -eq 'Json' -and -not $content.EndsWith("`n")) { $content += "`n" }
            [System.IO.File]::WriteAllText($full, $content, [System.Text.UTF8Encoding]::new($false))
            Write-Verbose "Wrote $Format to $full"
        }
        else { $text }
    }
}
