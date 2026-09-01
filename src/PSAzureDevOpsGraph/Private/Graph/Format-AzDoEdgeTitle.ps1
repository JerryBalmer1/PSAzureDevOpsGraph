function Format-AzDoEdgeTitle {
    <#
    .SYNOPSIS
        A one-line description of an edge, for a tooltip.
    .DESCRIPTION
        Names only the optional fields the edge actually carries. An edge with
        no alias says nothing about aliases rather than saying the alias is
        empty.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] $Edge)

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add("$($Edge.from) -> $($Edge.to)")
    $parts.Add("kind: $($Edge.kind)")
    foreach ($name in 'ref', 'refKind', 'alias', 'reason') {
        if ($Edge.PSObject.Properties[$name] -and $Edge.$name) {
            $parts.Add("${name}: $($Edge.$name)")
        }
    }
    $parts -join '  |  '
}
