function Split-AzDoReference {
    <#
    .SYNOPSIS
        Splits a template reference into its path and its @alias, keeping the raw text.
    .DESCRIPTION
        The raw text is kept exactly as it appeared - templates/steps-build.yml@mainPipelines
        and not a normalised form - because that is what the graph carries and
        what a reader has to match against the file.
    .OUTPUTS
        PSAzureDevOpsGraph.Reference
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateSet('template', 'extends')] [string] $Kind,
        [Parameter(Mandatory)] [string] $Reference
    )

    $path = $Reference
    $alias = $null
    $at = $Reference.LastIndexOf('@')
    if ($at -gt 0) {
        $path = $Reference.Substring(0, $at)
        $alias = $Reference.Substring($at + 1)
    }

    [pscustomobject] @{
        PSTypeName = 'PSAzureDevOpsGraph.Reference'
        Kind       = $Kind
        Reference  = $Reference
        Path       = $path
        Alias      = $alias
        Repository = $null
    }
}
