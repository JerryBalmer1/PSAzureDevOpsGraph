Set-StrictMode -Version 3.0

<#
The only path this module takes to Azure DevOps.

Two things are structural rather than conventional here:

1.  The HTTP method is not a parameter. It is 'Get', always. A caller cannot
    ask this function to POST, and there is no switch that changes it. The
    brief forbids queueing a pipeline or writing anything, permanently; a
    read-only guarantee that depends on every caller passing the right verb
    is not a guarantee.

2.  The token is read from $env:AZDO_PAT here and nowhere else. It is never a
    parameter, never returned, and never written into a message or a URL.
#>

function Get-AzDoAuthorizationHeader {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $pat = $env:AZDO_PAT

    if ([string]::IsNullOrWhiteSpace($pat)) {
        throw 'The environment variable AZDO_PAT is not set. PSAzureDevOpsGraph reads its personal access token from AZDO_PAT and from nowhere else: it does not prompt, does not read a file, and has no parameter for one. Set AZDO_PAT to a token with Code (read) and Build (read) scopes for the organisation you are querying.'
    }

    # ':<pat>' is the Azure DevOps basic-auth convention: empty user, token as
    # password. Built here so no caller ever holds the encoded form either.
    $pair  = ':' + $pat
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)

    return @{
        Authorization = 'Basic ' + [System.Convert]::ToBase64String($bytes)
        Accept        = 'application/json'
    }
}

function ConvertTo-AzDoQueryString {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowNull()] $Query)

    if ($null -eq $Query -or $Query.Count -eq 0) { return '' }

    $pairs = foreach ($key in $Query.Keys) {
        $value = $Query[$key]
        if ($null -eq $value) { continue }
        '{0}={1}' -f [System.Uri]::EscapeDataString([string]$key),
                     [System.Uri]::EscapeDataString([string]$value)
    }

    if (-not $pairs) { return '' }
    return '?' + ($pairs -join '&')
}

function Invoke-AzDoRestMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Organisation,

        # Optional so that a handful of organisation-scoped routes stay
        # reachable, but every route this module actually uses is project
        # scoped: the fixture's token has no vso.profile scope.
        [Parameter()][string] $Project,

        [Parameter(Mandatory)][string] $Resource,

        [Parameter()][hashtable] $Query,

        [Parameter()][string] $ApiVersion = '7.1',

        [Parameter()][switch] $Raw,

        [Parameter()][int] $TimeoutSeconds = 100
    )

    $base = 'https://dev.azure.com/{0}' -f [System.Uri]::EscapeDataString($Organisation)
    if (-not [string]::IsNullOrWhiteSpace($Project)) {
        $base = '{0}/{1}' -f $base, [System.Uri]::EscapeDataString($Project)
    }

    $q = @{}
    if ($Query) { foreach ($k in $Query.Keys) { $q[$k] = $Query[$k] } }
    $q['api-version'] = $ApiVersion

    $uri = '{0}/_apis/{1}{2}' -f $base, $Resource.TrimStart('/'), (ConvertTo-AzDoQueryString -Query $q)

    $headers = Get-AzDoAuthorizationHeader
    if ($Raw) { $headers['Accept'] = 'text/plain' }

    # The URI is safe to log: the token travels in a header, never in the URL.
    Write-Verbose ('GET {0}' -f $uri)

    $attempt = 0
    $maxAttempts = 4

    while ($true) {
        $attempt++
        try {
            $params = @{
                Uri             = $uri
                Method          = 'Get'          # not a parameter, by design
                Headers         = $headers
                TimeoutSec      = $TimeoutSeconds
                ErrorAction     = 'Stop'
                UseBasicParsing = $true
            }

            if ($Raw) {
                return (Invoke-WebRequest @params).Content
            }

            return Invoke-RestMethod @params
        }
        catch {
            $status = $null
            if ($_.Exception.PSObject.Properties.Name -contains 'Response' -and $_.Exception.Response) {
                try { $status = [int]$_.Exception.Response.StatusCode } catch { $status = $null }
            }

            $retryable = $status -in @(429, 500, 502, 503, 504)

            if ($retryable -and $attempt -lt $maxAttempts) {
                $delay = [Math]::Pow(2, $attempt)
                Write-Verbose ('{0} from Azure DevOps; retrying in {1}s (attempt {2}/{3})' -f $status, $delay, $attempt, $maxAttempts)
                Start-Sleep -Seconds $delay
                continue
            }

            if ($status -eq 401 -or $status -eq 203) {
                throw "Azure DevOps rejected the credential (HTTP $status) for $uri. Check that AZDO_PAT is current and carries Code (read) and Build (read) scopes for organisation '$Organisation'."
            }

            if ($status -eq 404) {
                # Callers distinguish a genuinely absent item from an error by
                # catching this and testing for 'AzDoNotFound'.
                throw "AzDoNotFound: $uri"
            }

            throw "Azure DevOps request failed for $uri : $($_.Exception.Message)"
        }
    }
}

function Test-AzDoNotFound {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] $ErrorRecord)

    return ([string]$ErrorRecord.Exception.Message).StartsWith('AzDoNotFound')
}
