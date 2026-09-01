function ConvertTo-AzDoGraphDot {
    <#
    .SYNOPSIS
        Render a dependency graph as Graphviz DOT.
    .DESCRIPTION
        Unresolved edges point at pseudo-nodes that are declared here rather
        than in the graph itself, and are drawn visibly differently: they are
        the answer the tool exists to give, and a rendering that hides them is
        worst exactly where it would be most useful.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Graph
    )

    $shape = @{ pipeline = 'box3d'; yaml = 'note'; repo = 'folder' }
    $style = @{
        definition         = 'color="#1f4e79", penwidth=2'
        template           = 'color="#2d6a4f"'
        extends            = 'color="#2d6a4f", style=bold'
        pipelineResource   = 'color="#7b2cbf", style=dashed'
        repositoryResource = 'color="#8a6d00"'
        checkout           = 'color="#8a6d00", style=dotted'
        unresolved         = 'color="#b00020", style=dashed, penwidth=2'
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('digraph PSAzureDevOpsGraph {')
    $lines.Add('    rankdir=LR;')
    $lines.Add('    graph [fontname="Segoe UI", labelloc="t", label=' + (ConvertTo-AzDoDotString "$($Graph.organisation) / $($Graph.project)") + '];')
    $lines.Add('    node  [fontname="Segoe UI", style=filled, fillcolor="#f5f5f5"];')
    $lines.Add('    edge  [fontname="Segoe UI", fontsize=9];')
    $lines.Add('')

    $known = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($node in $Graph.nodes) {
        $null = $known.Add($node.id)
        $lines.Add("    $(ConvertTo-AzDoDotString $node.id) [label=$(ConvertTo-AzDoDotString $node.name), shape=$($shape[$node.kind])];")
    }

    # Pseudo-nodes for unresolved targets, so the edge has somewhere to land.
    foreach ($edge in $Graph.edges) {
        if ($edge.kind -ne 'unresolved') { continue }
        if ($known.Add($edge.to)) {
            $lines.Add("    $(ConvertTo-AzDoDotString $edge.to) [label=$(ConvertTo-AzDoDotString $edge.to), shape=octagon, style=""filled,dashed"", fillcolor=""#ffe8e8"", color=""#b00020""];")
        }
    }

    $lines.Add('')
    foreach ($edge in $Graph.edges) {
        $label = if ($edge.PSObject.Properties['reason'] -and $edge.reason) { "$($edge.kind): $($edge.reason)" } else { $edge.kind }
        $lines.Add("    $(ConvertTo-AzDoDotString $edge.from) -> $(ConvertTo-AzDoDotString $edge.to) [label=$(ConvertTo-AzDoDotString $label), $($style[$edge.kind])];")
    }
    $lines.Add('}')
    $lines -join [Environment]::NewLine
}
