function ConvertTo-AzDoReference {
    <#
    .SYNOPSIS
        One reference record, with the raw text and the @alias kept separate.
    .DESCRIPTION
        Ref is the reference exactly as it appeared in the YAML, including any
        @alias suffix, because that is what a reader has to match against the
        file. Path and Alias are the parsed halves, and which of them is set is
        what decides between the two resolution rules.
    .PARAMETER RefKind
        template, extends, repositoryResource, pipelineResource or checkout.
    .PARAMETER Ref
        The reference text as written.
    .PARAMETER Alias
        The alias, for reference kinds that carry one explicitly.
    .PARAMETER Target
        A target name, for resource references that name one directly.
    .OUTPUTS
        PSAzureDevOpsGraph.Reference
    #>
    [CmdletBinding()]
    [OutputType('PSAzureDevOpsGraph.Reference')]
    param(
        [Parameter(Mandatory)] [string] $RefKind,
        [Parameter(Mandatory)] [string] $Ref,
        [string] $Alias,
        [string] $Target
    )

    $refPath = $Ref
    $refAlias = $Alias

    if ($RefKind -in @('template', 'extends')) {
        # path@alias. The presence of the alias half decides which resolution
        # rule applies, so it is split out once here and never re-derived.
        $at = $Ref.IndexOf('@')
        if ($at -ge 0) {
            $refPath = $Ref.Substring(0, $at)
            $refAlias = $Ref.Substring($at + 1)
        } else {
            $refPath = $Ref
            $refAlias = $null
        }
    }

    [pscustomobject]@{
        PSTypeName = 'PSAzureDevOpsGraph.Reference'
        RefKind    = $RefKind
        Ref        = $Ref
        Path       = $refPath
        Alias      = $refAlias
        Target     = $Target
    }
}
