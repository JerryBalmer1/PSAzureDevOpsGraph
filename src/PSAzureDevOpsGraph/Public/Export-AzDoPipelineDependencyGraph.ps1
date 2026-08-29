function Export-AzDoPipelineDependencyGraph {
    <#
        .SYNOPSIS
            Writes a dependency graph as JSON, DOT, or a self-contained HTML page.

        .DESCRIPTION
            The JSON form is the contract in fixture/graph.schema.json, whose
            top level forbids additional properties. Only the six declared
            fields are written; anything the in-memory graph carries for the
            caller's convenience - the recorded cycle back edges, for instance -
            is deliberately dropped here rather than smuggled into the file.

            The HTML form is self-contained on purpose: no external script,
            stylesheet, @import or http reference of any kind, so it renders
            from a file:// URL on a machine with no network. Unresolved targets
            are drawn as pseudo-nodes and marked, because they are the answer
            the tool exists to give.

        .PARAMETER Graph
            A graph from Get-AzDoPipelineDependencyGraph.

        .PARAMETER Path
            The file to write.

        .PARAMETER Format
            Json (default), Dot, or Html.

        .EXAMPLE
            $graph | Export-AzDoPipelineDependencyGraph -Path ./graph.json

            Writes the schema-shaped JSON.

        .EXAMPLE
            $graph | Export-AzDoPipelineDependencyGraph -Path ./graph.html -Format Html

            Writes a standalone page that opens with no network access.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [pscustomobject] $Graph,
        [Parameter(Mandatory)] [string] $Path,
        [ValidateSet('Json', 'Dot', 'Html')] [string] $Format = 'Json'
    )

    process {
        $nodes = @($Graph.nodes)
        $edges = @($Graph.edges)

        if ($Format -eq 'Json') {
            $payload = [ordered]@{
                version      = $Graph.version
                organisation = $Graph.organisation
                project      = $Graph.project
                generatedBy  = $Graph.generatedBy
                nodes        = $nodes
                edges        = $edges
            }
            $text = $payload | ConvertTo-Json -Depth 12
        }
        elseif ($Format -eq 'Dot') {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('digraph pipelines {')
            $lines.Add('  rankdir=LR;')
            foreach ($node in $nodes) {
                $shape = switch ($node.kind) { 'pipeline' { 'box' } 'repo' { 'folder' } default { 'ellipse' } }
                $lines.Add(('  "{0}" [label="{1}", shape={2}];' -f $node.id, $node.name, $shape))
            }
            foreach ($edge in $edges) {
                $style = if ($edge.kind -eq 'unresolved') { 'dashed' } else { 'solid' }
                $lines.Add(('  "{0}" -> "{1}" [label="{2}", style={3}];' -f
                        $edge.from, $edge.to, $edge.kind, $style))
            }
            $lines.Add('}')
            $text = $lines -join "`n"
        }
        else {
            $known = @{}
            foreach ($node in $nodes) { $known[$node.id] = $true }

            $rows = [System.Collections.Generic.List[string]]::new()
            foreach ($edge in ($edges | Sort-Object -Property { $_.from }, { $_.to })) {
                $unresolved = $edge.kind -eq 'unresolved'
                $missing = -not $known.ContainsKey($edge.to)
                $class = if ($unresolved) { 'unresolved' } else { $edge.kind }
                $target = [System.Net.WebUtility]::HtmlEncode([string]$edge.to)
                if ($missing) { $target = "$target <em>(pseudo-node)</em>" }
                $rows.Add(('<tr class="{0}"><td>{1}</td><td><span class="k">{2}</span></td><td>{3}</td><td>{4}</td></tr>' -f
                        $class,
                        [System.Net.WebUtility]::HtmlEncode([string]$edge.from),
                        [System.Net.WebUtility]::HtmlEncode([string]$edge.kind),
                        $target,
                        [System.Net.WebUtility]::HtmlEncode([string]($edge.reason ?? $edge.ref))))
            }

            $counts = $nodes | Group-Object -Property { $_.kind } | ForEach-Object {
                '<li><b>{0}</b> {1}</li>' -f $_.Count, $_.Name
            }

            $text = @"
<!doctype html>
<meta charset="utf-8">
<title>Pipeline dependency graph - $([System.Net.WebUtility]::HtmlEncode([string]$Graph.project))</title>
<style>
 body{font:14px system-ui,sans-serif;margin:2rem;color:#111;background:#fff}
 h1{font-size:1.2rem} ul{margin:0 0 1rem 1rem;padding:0}
 table{border-collapse:collapse;width:100%} td{padding:.25rem .5rem;border-bottom:1px solid #eee}
 .k{font-family:ui-monospace,monospace;font-size:.85em;color:#555}
 tr.unresolved{background:#fff4f4} tr.unresolved .k{color:#b00}
 em{color:#b00;font-style:normal;font-size:.85em}
</style>
<h1>$([System.Net.WebUtility]::HtmlEncode([string]$Graph.organisation)) / $([System.Net.WebUtility]::HtmlEncode([string]$Graph.project))</h1>
<ul>$($counts -join '')<li><b>$($edges.Count)</b> edges</li></ul>
<table>$($rows -join "`n")</table>
"@
        }

        Set-Content -LiteralPath $Path -Value $text -Encoding utf8NoBOM
        Get-Item -LiteralPath $Path
    }
}
