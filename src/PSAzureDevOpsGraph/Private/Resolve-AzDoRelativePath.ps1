function Resolve-AzDoRelativePath {
    <#
    .SYNOPSIS
        Normalises a repository-relative path, collapsing '.' and '..'.
    .DESCRIPTION
        Paths are always forward-slashed and never anchored to the filesystem:
        these are paths inside an Azure DevOps Git repository, not on this
        machine, so [System.IO.Path] would resolve them against the wrong root
        and would use the wrong separator on Windows.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # Directory the reference is relative to. Empty means the repository root.
        [AllowEmptyString()][string]$BaseDirectory,
        [Parameter(Mandatory)][string]$Path
    )

    $candidate = $Path -replace '\\', '/'
    if ($candidate.StartsWith('/')) {
        # Anchored at the repository root regardless of the referring file.
        $candidate = $candidate.TrimStart('/')
        $BaseDirectory = ''
    }
    elseif ($BaseDirectory) {
        $candidate = ($BaseDirectory.Trim('/') + '/' + $candidate)
    }

    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in ($candidate -split '/')) {
        if ($segment -eq '' -or $segment -eq '.') { continue }
        if ($segment -eq '..') {
            if ($out.Count -gt 0) { $out.RemoveAt($out.Count - 1) }
            continue
        }
        $out.Add($segment)
    }
    $out -join '/'
}
