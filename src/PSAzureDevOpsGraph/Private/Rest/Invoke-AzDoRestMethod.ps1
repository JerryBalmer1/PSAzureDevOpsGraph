function Invoke-AzDoRestMethod {
    <#
    .SYNOPSIS
        One paged read-only GET against a project-scoped Azure DevOps route.
    .DESCRIPTION
        GET only. Azure DevOps pages with a continuation token in a RESPONSE
        HEADER rather than in the body, so this uses Invoke-WebRequest -
        Invoke-RestMethod discards the headers and silently returns the first
        page only.

        The request URL never carries the token, and no failure message here
        repeats the URL.
    .OUTPUTS
        System.Object
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [hashtable] $Query = @{},
        [switch] $AllowNotFound
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $token = $null
    do {
        $pairs = @($Query.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString([string] $_.Value))" })
        if ($token) { $pairs += "continuationToken=$([uri]::EscapeDataString($token))" }
        $full = if ($pairs.Count) { "$Uri`?$($pairs -join '&')" } else { $Uri }

        try {
            $response = Invoke-WebRequest -Uri $full -Headers (Get-AzDoAuthHeader) -Method Get -ErrorAction Stop
        } catch {
            $status = $null
            if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
                $status = [int] $_.Exception.Response.StatusCode
            }
            if ($status -eq 404 -and $AllowNotFound) { return $null }
            if ($status -eq 401) {
                throw 'Azure DevOps returned 401. The token in AZDO_PAT lacks the required scope; it needs Code (Read) and Build (Read).'
            }
            throw
        }

        # 203 with an HTML body is the sign-in page. It arrives as a success
        # status and means the PAT is wrong or expired.
        $contentType = [string] ($response.Headers['Content-Type'] | Select-Object -First 1)
        if ($contentType -notmatch 'application/json') {
            throw 'Azure DevOps returned a non-JSON response. This is usually the sign-in page, which means the token in AZDO_PAT is wrong or expired.'
        }

        $body = $response.Content | ConvertFrom-Json
        if ($null -ne $body.PSObject.Properties['value']) { $items.AddRange(@($body.value)) }
        else { $items.Add($body) }

        $token = $response.Headers['x-ms-continuationtoken'] | Select-Object -First 1
    } while ($token)

    $items
}
