function New-AzDoReferenceRecord {
    <#
    .SYNOPSIS
        One parsed reference, with the raw text and any alias kept separate.
    .DESCRIPTION
        Reference is the text exactly as it appeared in the YAML -
        'templates/steps-build.yml@mainPipelines' and not a normalised form -
        because that is what the graph contract carries on the edge. Alias and
        Path are the parsed halves, kept beside it rather than instead of it.
    #>
    # PSUseShouldProcessForStateChangingFunctions: the rule is about changing
    # SYSTEM state, and this function allocates a PSCustomObject and returns it.
    # It reaches no network, no filesystem and no Azure DevOps route, so there
    # is nothing a -WhatIf could preview and nothing a -Confirm could decline.
    # Suppressed on this one function rather than repository-wide, so the rule
    # stays on for code not yet written. Removable if this ever acquires a side
    # effect, which would be the moment it should stop being called New-.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateSet('template', 'extends', 'repositoryResource', 'pipelineResource', 'checkout')]
        [string] $Kind,
        [Parameter(Mandatory)] [string] $Reference,
        [string] $Alias,
        [string] $Name,
        [string] $Type
    )

    $path = $null
    $parsedAlias = $Alias
    if ($Kind -in 'template', 'extends') {
        # The @alias suffix is what selects the second resolution rule, so it is
        # parsed out here once rather than at every call site.
        $at = $Reference.IndexOf('@')
        if ($at -ge 0) {
            $path = $Reference.Substring(0, $at)
            $parsedAlias = $Reference.Substring($at + 1)
        } else {
            $path = $Reference
            $parsedAlias = $null
        }
    }

    [pscustomobject]@{
        PSTypeName = 'PSAzureDevOpsGraph.Reference'
        Kind       = $Kind
        Reference  = $Reference
        Alias      = if ([string]::IsNullOrEmpty($parsedAlias)) { $null } else { $parsedAlias }
        Path       = $path
        Name       = if ([string]::IsNullOrEmpty($Name)) { $null } else { $Name }
        Type       = if ([string]::IsNullOrEmpty($Type)) { $null } else { $Type }
    }
}
