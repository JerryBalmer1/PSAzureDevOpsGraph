function Get-AzDoAuthHeader {
    <#
    .SYNOPSIS
        The Basic auth header for Azure DevOps, built from $env:AZDO_PAT.
    .DESCRIPTION
        The PAT comes from the environment variable and from nowhere else -- not
        a parameter, not a file, not a URL. A value passed as a parameter ends up
        in PSReadLine history, in Start-Transcript output and in the ScriptBlock
        logging event log, and a PAT is a bearer credential for an entire
        organisation.

        The header is built at the call site each time rather than cached in a
        module-scoped variable, so a -Verbose dump or an error record has nothing
        to surface.
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
