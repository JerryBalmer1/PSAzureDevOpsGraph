function Invoke-AzDoRestMethod {
    <#
    .SYNOPSIS
        GET an Azure DevOps project-scoped route, following continuation tokens.
    .DESCRIPTION
        Azure DevOps pages with a continuation token in a RESPONSE HEADER, not
        in the body, so this uses Invoke-WebRequest - Invoke-RestMethod discards
        the headers and silently returns only the first page.

        GET only. The module never queues, runs, creates, updates or deletes
        anything, and there is no switch that changes that.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [string]    $Uri,
        [hashtable]                        $Query = @{},
        [int]                              $MaximumRetryCount = 5
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $token = $null
    do {
        $pairs = @($Query.GetEnumerator() | ForEach-Object {
                "$($_.Key)=$([uri]::EscapeDataString([string] $_.Value))"
            })
        if ($token) { $pairs += "continuationToken=$([uri]::EscapeDataString($token))" }
        $full = if ($pairs.Count) { "$Uri`?$($pairs -join '&')" } else { $Uri }

        $response = Invoke-AzDoWebRequest -Uri $full -MaximumRetryCount $MaximumRetryCount
        if ($null -eq $response) { return $null }

        $body = $response.Content | ConvertFrom-Json
        if ($null -ne $body.PSObject.Properties['value']) { $items.AddRange(@($body.value)) }
        else { $items.Add($body) }

        $token = $response.Headers['x-ms-continuationtoken'] | Select-Object -First 1
    } while ($token)

    , $items.ToArray()
}
