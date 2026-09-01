function ConvertTo-AzDoGraphDot {
    <#
    .SYNOPSIS
        A graph as Graphviz DOT text.
    .DESCRIPTION
        Unresolved targets are drawn as pseudo-nodes, dashed and distinct from
        real ones. They are the answer the tool exists to give, so they must not
        look like an ordinary dependency and must not be omitted.
    .PARAMETER Graph
        A graph from Get-AzDoPipelineDependencyGraph.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] $Graph)

    $shape = @{ pipeline = 'box3d'; yaml = 'note'; repo = 'folder' }
    $fill = @{ pipeline = '#dbeafe'; yaml = '#ecfdf5'; repo = '#fef3c7' }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('digraph PSAzureDevOpsGraph {')
    $lines.Add('  rankdir=LR;')
    $lines.Add('  node [style="filled,rounded" fontname="Segoe UI,Helvetica,sans-serif" fontsize=10];')
    $lines.Add('  edge [fontname="Segoe UI,Helvetica,sans-serif" fontsize=8];')
    $lines.Add('')

    $real = @{}
    foreach ($node in $Graph.nodes) {
        $real[$node.id] = $true
        $label = if ($node.kind -eq 'yaml') { "$($node.repo)/$($node.name)" } else { $node.name }
        $lines.Add("  `"$($node.id)`" [label=`"$label`" shape=$($shape[$node.kind]) fillcolor=`"$($fill[$node.kind])`"];")
    }

    # Pseudo-nodes for every edge endpoint that is not a real node.
    $lines.Add('')
    $pseudo = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($edge in $Graph.edges) {
        if (-not $real.ContainsKey($edge.to) -and $pseudo.Add($edge.to)) {
            $lines.Add("  `"$($edge.to)`" [label=`"$($edge.to)`" shape=octagon style=`"filled,dashed`" fillcolor=`"#fee2e2`" color=`"#b91c1c`"];")
        }
    }

    $lines.Add('')
    foreach ($edge in $Graph.edges) {
        $label = if ($edge.kind -eq 'unresolved') { "$($edge.refKind): $($edge.reason)" } else { $edge.kind }
        $style = if ($edge.kind -eq 'unresolved') { ' style=dashed color="#b91c1c"' } else { '' }
        $lines.Add("  `"$($edge.from)`" -> `"$($edge.to)`" [label=`"$label`"$style];")
    }

    $lines.Add('}')
    $lines -join [Environment]::NewLine
}
