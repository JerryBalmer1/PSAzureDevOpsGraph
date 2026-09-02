function Invoke-AzDoRestMethod {
    <#
    .SYNOPSIS
        A paged, read-only GET against the Azure DevOps REST API.
    .DESCRIPTION
        Azure DevOps pages with a continuation token in a RESPONSE HEADER rather
        than in the body, so this uses Invoke-WebRequest -- Invoke-RestMethod
        discards the headers and silently returns only the first page.

        GET only. The module never queues, runs, creates, updates or deletes
        anything, and there is no switch that changes that.

        Two Azure DevOps answers need handling by hand rather than by the
        pipeline's default error behaviour:

        - 203 with an HTML body is the sign-in page. It means the PAT is wrong or
          expired, and it arrives as a SUCCESS status, so the content type has to
          be checked before anything is parsed.
        - 404 on an item fetch means the file is not in that repository. For a
          dependency graph that is a result, not an exception.
    .PARAMETER Uri
        The full route, without a query string.
    .PARAMETER Query
        Query parameters, added and escaped by this function.
    .PARAMETER NotFoundIsNull
        Return $null on a 404 instead of throwing. Item fetches want this; list
        endpoints do not, because a 404 there is a wrong route.
    .OUTPUTS
        System.Object
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [hashtable] $Query = @{},
        [switch] $NotFoundIsNull
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $token = $null
    $attempt = 0

    do {
        $pairs = @($Query.GetEnumerator() | ForEach-Object {
                "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))"
            })
        if ($token) { $pairs += "continuationToken=$([uri]::EscapeDataString($token))" }
        $full = if ($pairs.Count) { "$Uri`?$($pairs -join '&')" } else { $Uri }

        # OUTSIDE the try. Built inside it, the "AZDO_PAT is not set" throw is
        # caught by the handler below and rewritten as an HTTP status that is not
        # there -- so the one error that names the fix gets replaced by one that
        # names nothing. The missing-credential failure is not a transport
        # failure and must not be handled as one.
        $headers = Get-AzDoAuthHeader

        try {
            $response = Invoke-WebRequest -Uri $full -Headers $headers -Method Get -MaximumRedirection 0 -ErrorAction Stop
        } catch {
            $status = $_.Exception.Response.StatusCode.value__

            if ($status -eq 404 -and $NotFoundIsNull) { return $null }

            if ($status -eq 429 -and $attempt -lt 5) {
                # Retry-After is in seconds. Fall back to a short backoff when
                # the header is absent.
                $after = 2
                try {
                    $header = $_.Exception.Response.Headers.GetValues('Retry-After') | Select-Object -First 1
                    if ($header) { $after = [int] $header }
                } catch {
                    $after = [math]::Pow(2, $attempt)
                }
                $attempt++
                Write-Verbose "Throttled by Azure DevOps; waiting $after second(s) before retry $attempt."
                Start-Sleep -Seconds $after
                continue
            }

            if ($status -eq 401) {
                throw 'Azure DevOps returned 401. The token in $env:AZDO_PAT lacks the required scope; it needs Code (Read) and Build (Read).'
            }

            # The request URL is deliberately not included in the message. It is
            # not secret in itself, but error records travel and this is the one
            # place a credential could be reintroduced by a later edit.
            throw "Azure DevOps returned HTTP $status for a $($Uri -replace '^https://[^/]+', '') request."
        }

        $attempt = 0

        $contentType = [string] ($response.Headers['Content-Type'] | Select-Object -First 1)
        if ($contentType -notmatch 'application/json') {
            throw 'Azure DevOps returned a non-JSON body (the sign-in page). The token in $env:AZDO_PAT is wrong or expired.'
        }

        $body = $response.Content | ConvertFrom-Json
        if ($null -ne $body.PSObject.Properties['value']) { $items.AddRange(@($body.value)) }
        else { $items.Add($body) }

        $token = $response.Headers['x-ms-continuationtoken'] | Select-Object -First 1
    } while ($token)

    $items
}
