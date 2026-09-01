function ConvertFrom-AzDoYamlDocument {
    <#
    .SYNOPSIS
        Parse YAML text into an object graph, or report why it could not be.
    .DESCRIPTION
        A document that will not parse is a RESULT, not a crash: a project with
        one malformed pipeline should still yield a graph for the others. The
        caller gets $null and a reason on the error stream.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try {
        ConvertFrom-Yaml -Yaml $Text -Ordered
    } catch {
        Write-Verbose "YAML did not parse: $($_.Exception.Message)"
        $null
    }
}
