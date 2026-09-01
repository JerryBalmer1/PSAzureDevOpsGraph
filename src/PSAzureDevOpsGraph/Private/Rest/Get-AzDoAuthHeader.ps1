function Get-AzDoAuthHeader {
    <#
    .SYNOPSIS
        The Basic auth header for Azure DevOps, built from $env:AZDO_PAT.
    .DESCRIPTION
        Built at the call site every time. It is deliberately not cached in a
        module-scoped variable, because a -Verbose dump or an error record could
        surface one.
    .OUTPUTS
        System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if (-not $env:AZDO_PAT) {
        throw 'AZDO_PAT is not set. Set $env:AZDO_PAT to a personal access token with Code (Read) and Build (Read) scope.'
    }

    $bytes = [Text.Encoding]::ASCII.GetBytes(":$($env:AZDO_PAT)")
    @{ Authorization = 'Basic ' + [Convert]::ToBase64String($bytes) }
}
