function ConvertTo-AzDoGraphDot {
    <#
    .SYNOPSIS
        Renders a dependency graph as Graphviz DOT.
    .DESCRIPTION
        Unresolved targets are pseudo-nodes and are drawn distinctly: they are
        the answer the tool exists to give, not a rendering accident.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [psobject] $Graph
    )

    $shape = @{ pipeline = 'box3d'; yaml = 'note'; repo = 'folder' }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('digraph PipelineDependencies {')
    $lines.Add('    rankdir=LR;')
    $lines.Add('    node [fontname="Segoe UI" fontsize=10];')
    $lines.Add('    edge [fontname="Segoe UI" fontsize=8];')

    $real = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($node in $Graph.nodes) {
        $null = $real.Add($node.id)
        $lines.Add("    `"$($node.id)`" [label=`"$($node.name)`" shape=$($shape[$node.kind]) style=filled fillcolor=`"#eef3f8`"];")
    }

    foreach ($edge in $Graph.edges) {
        if (-not $real.Contains($edge.to)) {
            $lines.Add("    `"$($edge.to)`" [label=`"$($edge.to)`" shape=octagon style=`"filled,dashed`" fillcolor=`"#fdecea`" color=`"#b3261e`"];")
            $null = $real.Add($edge.to)
        }
    }

    foreach ($edge in $Graph.edges) {
        $label = if ($edge.PSObject.Properties['reason'] -and $edge.reason) { "$($edge.kind): $($edge.reason)" } else { $edge.kind }
        $style = if ($edge.kind -eq 'unresolved') { ' style=dashed color="#b3261e"' } else { '' }
        $lines.Add("    `"$($edge.from)`" -> `"$($edge.to)`" [label=`"$label`"$style];")
    }

    $lines.Add('}')
    $lines -join [Environment]::NewLine
}
