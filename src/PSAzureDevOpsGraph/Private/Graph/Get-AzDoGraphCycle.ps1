function Invoke-AzDoCycleWalk {
    <#
        .SYNOPSIS
            Depth-first half of cycle detection. Colours nodes as it goes.

        .DESCRIPTION
            Three colours. Absent is unvisited, 1 is "on the current stack", 2
            is "finished". An edge into a node coloured 1 is a back edge and
            therefore a real cycle; an edge into a node coloured 2 is merely a
            second path to somewhere already finished, which is a diamond and
            not a cycle at all.

            Getting that distinction wrong is why a breadth-first "have I seen
            this target" test cannot report cycles: it calls every shared
            template a cycle.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)] [string] $Node,
        [Parameter(Mandatory)] [hashtable] $Adjacency,
        [Parameter(Mandatory)] [hashtable] $Colour,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.List[string]] $Found
    )

    $Colour[$Node] = 1

    if ($Adjacency.ContainsKey($Node)) {
        foreach ($next in $Adjacency[$Node]) {
            if (-not $Colour.ContainsKey($next)) {
                Invoke-AzDoCycleWalk -Node $next -Adjacency $Adjacency -Colour $Colour -Found $Found
            }
            elseif ($Colour[$next] -eq 1) {
                $Found.Add("$Node -> $next")
            }
        }
    }

    $Colour[$Node] = 2
}

function Get-AzDoGraphCycle {
    <#
        .SYNOPSIS
            Returns the back edges - the real cycles - among a graph's file
            inclusion edges.

        .DESCRIPTION
            Only template and extends edges are followed. A repository or
            pipeline resource is a dependency, not an inclusion, and cannot
            take part in a template inclusion cycle.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[string]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Edge
    )

    $adjacency = @{}
    foreach ($item in $Edge) {
        if ($item.kind -notin @('template', 'extends')) { continue }
        $from = [string] $item.from
        if (-not $adjacency.ContainsKey($from)) {
            $adjacency[$from] = [System.Collections.Generic.List[string]]::new()
        }
        $adjacency[$from].Add([string] $item.to)
    }

    $colour = @{}
    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($start in @($adjacency.Keys)) {
        if ($colour.ContainsKey($start)) { continue }
        Invoke-AzDoCycleWalk -Node $start -Adjacency $adjacency -Colour $colour -Found $found
    }

    , $found
}
