function Invoke-AzDoWebRequest {
    <#
    .SYNOPSIS
        One GET against Azure DevOps, with the three responses worth handling by
        hand.
    .DESCRIPTION
        404  the item is absent. For a dependency graph that is a RESULT - an
             unresolved reference - not an exception, so this returns $null.
        203  Azure DevOps' sign-in page, which arrives as a success status with
             an HTML body. It means the PAT is wrong or expired.
        429  throttled. Honours Retry-After and retries; the URL is never put in
             the message.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [int]                           $MaximumRetryCount = 5
    )

    for ($attempt = 0; $attempt -le $MaximumRetryCount; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Uri -Headers (Get-AzDoAuthHeader) `
                -Method Get -MaximumRedirection 0 -ErrorAction Stop

            if ([int] $response.StatusCode -eq 203) {
                throw 'Azure DevOps returned its sign-in page (203). The PAT in $env:AZDO_PAT is wrong or expired.'
            }
            $contentType = [string] ($response.Headers['Content-Type'] | Select-Object -First 1)
            if ($contentType -and $contentType -notmatch 'json') {
                throw "Azure DevOps returned '$contentType' rather than JSON. The PAT in `$env:AZDO_PAT is wrong or expired."
            }
            return $response
        } catch {
            $status = $null
            if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
                $status = [int] $_.Exception.Response.StatusCode
            }

            if ($status -eq 404) { return $null }

            if ($status -eq 429 -and $attempt -lt $MaximumRetryCount) {
                $after = 2
                $header = $_.Exception.Response.Headers
                if ($header -and $header.RetryAfter -and $header.RetryAfter.Delta) {
                    $after = [int] $header.RetryAfter.Delta.TotalSeconds
                }
                Write-Verbose "Throttled by Azure DevOps; retrying in $after second(s)."
                Start-Sleep -Seconds ([math]::Max(1, $after))
                continue
            }

            if ($status -eq 401) {
                throw 'Azure DevOps returned 401. The token in $env:AZDO_PAT lacks the required scopes: Code (Read) and Build (Read).'
            }

            # The request URL is deliberately not included: URLs are logged by
            # proxies and captured in exception messages.
            throw
        }
    }
    throw "Azure DevOps kept throttling after $MaximumRetryCount retries."
}
