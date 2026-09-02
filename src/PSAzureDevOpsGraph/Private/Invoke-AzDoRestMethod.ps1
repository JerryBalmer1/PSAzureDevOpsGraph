function Invoke-AzDoRestMethod {
    <#
    .SYNOPSIS
        Issues one read-only Azure DevOps REST request, with retry on throttling.
    .DESCRIPTION
        Every request this module makes goes through here. The method is fixed to
        GET: the module is read-only by construction rather than by discipline,
        so there is no parameter that could carry POST, PATCH or DELETE.

        429 and 5xx responses are retried with backoff, honouring Retry-After
        when Azure DevOps supplies it.
    #>
    [CmdletBinding()]
    param(
        # API path below _apis, e.g. 'git/repositories'.
        [Parameter(Mandatory)]
        [string]$ApiPath,

        [Parameter(Mandatory)]
        [string]$Organisation,

        # Omitted for organisation-scoped endpoints. All fixture traffic is
        # project-scoped.
        [string]$Project,

        [hashtable]$Query = @{},

        [string]$ApiVersion = '7.1',

        [int]$MaximumRetryCount = 5
    )

    $headers = Get-AzDoAuthorizationHeader

    $segments = @('https://dev.azure.com', [uri]::EscapeDataString($Organisation))
    if ($Project) { $segments += [uri]::EscapeDataString($Project) }
    $segments += '_apis'
    $segments += $ApiPath.Trim('/')
    $url = $segments -join '/'

    $pairs = @("api-version=$ApiVersion")
    foreach ($key in $Query.Keys) {
        $value = $Query[$key]
        if ($null -eq $value) { continue }
        $pairs += '{0}={1}' -f $key, [uri]::EscapeDataString([string]$value)
    }
    $url = $url + '?' + ($pairs -join '&')

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            Write-Verbose "GET $url (attempt $attempt)"
            return Invoke-RestMethod -Method Get -Uri $url -Headers $headers -ErrorAction Stop
        }
        catch {
            $response = $_.Exception.Response
            $status   = if ($response) { [int]$response.StatusCode } else { 0 }

            $retryable = ($status -eq 429) -or ($status -ge 500 -and $status -le 599) -or ($status -eq 0)
            if (-not $retryable -or $attempt -ge $MaximumRetryCount) {
                if ($status -eq 401 -or $status -eq 203) {
                    throw "Azure DevOps rejected the credential in `$env:AZDO_PAT (HTTP $status) for $url. Check that the token is current and has Code (read) and Build (read) scopes."
                }
                throw "Azure DevOps request failed (HTTP $status) for $url : $($_.Exception.Message)"
            }

            $delay = [math]::Min([math]::Pow(2, $attempt), 30)
            if ($response -and $response.Headers -and $response.Headers.Contains('Retry-After')) {
                $after = ($response.Headers.GetValues('Retry-After') | Select-Object -First 1)
                $parsed = 0
                if ([int]::TryParse($after, [ref]$parsed) -and $parsed -gt 0) { $delay = $parsed }
            }
            Write-Verbose "Retrying in ${delay}s (HTTP $status)"
            Start-Sleep -Seconds $delay
        }
    }
}
