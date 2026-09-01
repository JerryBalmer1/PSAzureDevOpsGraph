function ConvertTo-AzDoHtmlText {
    <#
    .SYNOPSIS
        Escape a string for HTML or SVG text content and attribute values.
    .DESCRIPTION
        Node ids and reference text come from pipeline YAML, which nobody in
        this module authored. Escaping happens here, once, rather than at each
        of the twenty call sites that would each have to remember.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyString()] [string] $Value)

    if ([string]::IsNullOrEmpty($Value)) { return '' }
    $Value -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&#39;'
}
