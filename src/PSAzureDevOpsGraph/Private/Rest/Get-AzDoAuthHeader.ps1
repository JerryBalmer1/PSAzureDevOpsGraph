function Get-AzDoAuthHeader {
    <#
        .SYNOPSIS
            Builds the Basic authorization header from $env:AZDO_PAT.

        .DESCRIPTION
            The personal access token is read from the environment and from
            nowhere else. It is never accepted as a parameter, never read from a
            file, and never placed in a URL: a value passed as a parameter ends
            up in PSReadLine history, in Start-Transcript output, and in
            ScriptBlock logging, and it is a bearer credential for an entire
            organisation.

            The header is built fresh at each call rather than cached, so that
            no module-scoped variable holds the token where an error record or a
            -Verbose dump could surface it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ([string]::IsNullOrWhiteSpace($env:AZDO_PAT)) {
        throw 'AZDO_PAT is not set. Set $env:AZDO_PAT to an Azure DevOps personal access token with Code (Read) and Build (Read) scope.'
    }

    $bytes = [System.Text.Encoding]::ASCII.GetBytes(":$($env:AZDO_PAT)")
    @{ Authorization = 'Basic ' + [Convert]::ToBase64String($bytes) }
}
