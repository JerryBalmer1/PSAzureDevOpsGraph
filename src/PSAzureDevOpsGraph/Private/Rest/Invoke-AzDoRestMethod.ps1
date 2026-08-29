function Invoke-AzDoRestMethod {
    <#
        .SYNOPSIS
            GETs an Azure DevOps REST route, following continuation tokens.

        .DESCRIPTION
            Read-only by construction: the method is fixed at GET and there is
            no parameter that can change it. Azure DevOps pages with a
            continuation token in a response header rather than in the body, so
            this uses Invoke-WebRequest - Invoke-RestMethod discards the
            headers.

            A 203 response carrying HTML is Azure DevOps' sign-in page arriving
            with a success status, which means the token is wrong or expired.
            That is reported as an authentication failure rather than parsed as
            data.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string] $Uri,

        [hashtable] $Query = @{},

        [switch] $Single
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $continuation = $null

    do {
        $pairs = @(
            foreach ($key in $Query.Keys) {
                '{0}={1}' -f $key, [uri]::EscapeDataString([string]$Query[$key])
            }
            if ($continuation) {
                'continuationToken={0}' -f [uri]::EscapeDataString($continuation)
            }
        )

        $full = if ($pairs.Count) { '{0}?{1}' -f $Uri, ($pairs -join '&') } else { $Uri }

        $response = Invoke-WebRequest -Uri $full -Headers (Get-AzDoAuthHeader) -Method Get -ErrorAction Stop

        $contentType = [string]($response.Headers['Content-Type'] | Select-Object -First 1)
        if ($contentType -match 'text/html') {
            throw 'Azure DevOps returned its sign-in page. The personal access token in AZDO_PAT is invalid, expired, or lacks the required scope.'
        }

        $body = $response.Content | ConvertFrom-Json

        if ($Single) {
            return $body
        }

        if ($body.PSObject.Properties.Name -contains 'value') {
            foreach ($item in @($body.value)) { $items.Add($item) }
        }
        else {
            $items.Add($body)
        }

        $continuation = [string]($response.Headers['x-ms-continuationtoken'] | Select-Object -First 1)
    }
    while (-not [string]::IsNullOrEmpty($continuation))

    , $items.ToArray()
}
