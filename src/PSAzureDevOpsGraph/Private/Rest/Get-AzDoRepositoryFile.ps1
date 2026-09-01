function Get-AzDoRepositoryFile {
    <#
    .SYNOPSIS
        Every file path in one repository, as repository-relative strings.
    .DESCRIPTION
        One call per repository rather than a 404 probe per reference. Besides
        being cheaper, it lets resolution answer "no such file" as a fact it
        holds rather than as an exception it caught, which is what makes
        Resolve-AzDoPipelineReference able to report file-not-found without a
        credential of its own.

        Folders are dropped; only files can be the target of a reference.
    .PARAMETER Organisation
        The Azure DevOps organisation.
    .PARAMETER Project
        The project name.
    .PARAMETER RepositoryId
        The repository GUID.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Organisation,
        [Parameter(Mandatory)] [string] $Project,
        [Parameter(Mandatory)] [string] $RepositoryId
    )

    $items = Invoke-AzDoRestMethod -Uri "https://dev.azure.com/$Organisation/$Project/_apis/git/repositories/$RepositoryId/items" -Query @{
        'recursionLevel' = 'Full'
        'api-version'    = '7.1'
    } -NotFoundIsNull

    foreach ($item in @($items)) {
        if ($null -eq $item) { continue }
        if ($item.PSObject.Properties['isFolder'] -and $item.isFolder) { continue }
        if ($null -eq $item.PSObject.Properties['path']) { continue }
        ([string] $item.path).TrimStart('/')
    }
}
