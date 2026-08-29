function Get-AzDoItemContent {
    <#
        .SYNOPSIS
            Fetches the text of one file from a repository, or $null if absent.

        .DESCRIPTION
            A 404 means the file is not in that repository. For a dependency
            graph that is a result - an unresolved reference with reason
            file-not-found - and not an exception, so it is returned as $null
            rather than thrown.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Organisation,
        [Parameter(Mandatory)] [string] $Project,
        [Parameter(Mandatory)] [string] $RepositoryId,
        [Parameter(Mandatory)] [string] $Path
    )

    $uri = 'https://dev.azure.com/{0}/{1}/_apis/git/repositories/{2}/items' -f $Organisation, $Project, $RepositoryId

    $query = @{
        'path'           = '/' + $Path.TrimStart('/')
        'includeContent' = 'true'
        '$format'        = 'json'
        'api-version'    = '7.1'
    }

    try {
        $item = Invoke-AzDoRestMethod -Uri $uri -Query $query -Single
    }
    catch {
        $status = $null
        if ($_.Exception.PSObject.Properties.Name -contains 'Response' -and $_.Exception.Response) {
            $status = [int] $_.Exception.Response.StatusCode
        }
        if ($status -eq 404) { return $null }
        throw
    }

    if ($null -eq $item) { return $null }
    if ($item.PSObject.Properties.Name -notcontains 'content') { return $null }

    [string] $item.content
}
