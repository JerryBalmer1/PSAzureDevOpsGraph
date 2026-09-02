function Get-AzDoAuthorizationHeader {
    <#
    .SYNOPSIS
        Builds the Authorization header from $env:AZDO_PAT.
    .DESCRIPTION
        The token is read from the environment and from nowhere else. There is
        deliberately no parameter, no file fallback and no prompt: a PAT that
        arrives as a parameter value is captured by PSReadLine history, by
        Start-Transcript, and by ScriptBlock logging, and it is a bearer
        credential for an entire organisation.

        The returned hashtable is built fresh on each call so that no long-lived
        module-scope variable holds the encoded credential.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $pat = $env:AZDO_PAT
    if ([string]::IsNullOrWhiteSpace($pat)) {
        throw 'The environment variable AZDO_PAT is not set. PSAzureDevOpsGraph reads its Azure DevOps personal access token from $env:AZDO_PAT and from nowhere else; it does not prompt and does not read a file.'
    }

    $bytes = [System.Text.Encoding]::ASCII.GetBytes(":$pat")
    @{
        Authorization = 'Basic ' + [System.Convert]::ToBase64String($bytes)
        Accept        = 'application/json'
    }
}
