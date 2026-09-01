function Resolve-AzDoRelativePath {
    <#
    .SYNOPSIS
        Normalise a repository-relative path, resolving . and .. segments.
    .DESCRIPTION
        Pure string work. There is no filesystem here -- these paths live in an
        Azure DevOps repository, and Resolve-Path would answer about the machine
        running the module instead.

        A reference beginning with / is repository-root-relative even without an
        alias, so BaseDirectory is ignored for those.
    .PARAMETER BaseDirectory
        The directory of the file making the reference, within its repository.
        Empty for a root-relative resolution.
    .PARAMETER Path
        The reference path, as written, with any @alias already removed.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $BaseDirectory = '',
        [Parameter(Mandatory)] [string] $Path
    )

    $normalised = $Path -replace '\\', '/'

    $combined = if ($normalised.StartsWith('/')) {
        $normalised
    } elseif ([string]::IsNullOrEmpty($BaseDirectory)) {
        $normalised
    } else {
        "$($BaseDirectory.TrimEnd('/'))/$normalised"
    }

    $stack = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in ($combined -split '/')) {
        if ($segment -eq '' -or $segment -eq '.') { continue }
        if ($segment -eq '..') {
            if ($stack.Count) { $stack.RemoveAt($stack.Count - 1) }
            continue
        }
        $stack.Add($segment)
    }

    $stack -join '/'
}
