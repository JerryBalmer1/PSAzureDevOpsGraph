function Resolve-AzDoRepositoryPath {
    <#
        .SYNOPSIS
            Normalises a repository-relative path, collapsing '.' and '..'.

        .DESCRIPTION
            Purely textual and rooted at the repository, so '..' can never
            escape above the repository root. Paths are always forward-slashed
            and never carry a leading slash: they are keys into a repository,
            not filesystem paths.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Path
    )

    $segments = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in ($Path -replace '\\', '/').Split('/')) {
        if ($segment -eq '' -or $segment -eq '.') { continue }
        if ($segment -eq '..') {
            if ($segments.Count -gt 0) { $segments.RemoveAt($segments.Count - 1) }
            continue
        }
        $segments.Add($segment)
    }

    $segments -join '/'
}
