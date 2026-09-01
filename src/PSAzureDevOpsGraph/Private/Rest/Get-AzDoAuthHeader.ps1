function Get-AzDoAuthHeader {
    <#
    .SYNOPSIS
        The Basic auth header for Azure DevOps, built from $env:AZDO_PAT.
    .DESCRIPTION
        Built at the call site each time rather than cached in a module-scoped
        variable that a -Verbose dump or an error record could surface.

        The token comes from the environment variable and from nowhere else.
        There is no parameter, no file, and no fallback: a value passed as a
        parameter ends up in PSReadLine history, in Start-Transcript output and
        in the ScriptBlock logging event log, and a PAT is a bearer credential
        for an entire organisation.
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
