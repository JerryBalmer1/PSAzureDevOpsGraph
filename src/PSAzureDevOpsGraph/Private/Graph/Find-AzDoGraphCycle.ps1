function Find-AzDoGraphCycle {
    <#
    .SYNOPSIS
        The cycles in an assembled edge list, as readable paths.
    .DESCRIPTION
        A REVISIT IS NOT A CYCLE. Two pipelines including one shared template
        reach that template twice, and a traversal that reports every
        second arrival as a back edge reports a diamond as a cycle -- which is
        the same defect as reporting no cycle, in the other direction. Only an
        edge into a node still on the current DFS stack closes one.

        Depth-first with three colours, iterative rather than recursive so a deep
        template chain cannot overflow the stack.
    .PARAMETER Edge
        The assembled edges.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Edge)

    $adjacency = @{}
    foreach ($item in $Edge) {
        if (-not $adjacency.ContainsKey($item.from)) {
            $adjacency[$item.from] = [System.Collections.Generic.List[string]]::new()
        }
        $adjacency[$item.from].Add($item.to)
    }

    # 0 unvisited, 1 on the current stack, 2 finished.
    $state = @{}
    $found = [System.Collections.Generic.List[string]]::new()

    foreach ($start in @($adjacency.Keys | Sort-Object)) {
        if ($state[$start]) { continue }

        $stack = [System.Collections.Generic.Stack[object]]::new()
        $path = [System.Collections.Generic.List[string]]::new()

        $state[$start] = 1
        $path.Add($start)
        $stack.Push([pscustomobject]@{ Node = $start; Index = 0 })

        while ($stack.Count) {
            $frame = $stack.Peek()

            # [string[]], and never the bare result of an if. A single-element
            # List returned from an if expression is UNROLLED to a scalar string,
            # and indexing that string yields a [char] -- which then misses every
            # string-keyed lookup silently, so the walk visits nothing and
            # reports no cycles at all.
            [string[]] $children = @()
            if ($adjacency.ContainsKey($frame.Node)) {
                $children = [string[]] $adjacency[$frame.Node]
            }

            if ($frame.Index -lt $children.Count) {
                $child = $children[$frame.Index]
                $frame.Index++

                if (-not $state[$child]) {
                    $state[$child] = 1
                    $path.Add($child)
                    $stack.Push([pscustomobject]@{ Node = $child; Index = 0 })
                } elseif ($state[$child] -eq 1) {
                    # Still on the stack: this edge closes a cycle.
                    $at = $path.IndexOf($child)
                    if ($at -ge 0) {
                        $found.Add(((@($path[$at..($path.Count - 1)]) + $child) -join ' -> '))
                    }
                }
            } else {
                $state[$frame.Node] = 2
                $null = $stack.Pop()
                if ($path.Count) { $path.RemoveAt($path.Count - 1) }
            }
        }
    }

    $found
}
