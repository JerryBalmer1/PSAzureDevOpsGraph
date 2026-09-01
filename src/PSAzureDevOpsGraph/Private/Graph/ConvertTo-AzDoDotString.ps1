function ConvertTo-AzDoDotString {
    <#
    .SYNOPSIS
        Quote and escape a string for a DOT attribute or node id.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Value)

    # DOT escapes with a backslash, so the backslash itself must be doubled
    # first or the second replacement would escape an escape.
    $backslash = [string][char] 92
    $escaped = $Value.Replace($backslash, $backslash + $backslash).Replace('"', $backslash + '"')
    '"' + $escaped + '"'
}
