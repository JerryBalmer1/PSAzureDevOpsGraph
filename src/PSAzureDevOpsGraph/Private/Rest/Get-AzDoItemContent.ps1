function Get-AzDoItemContent {
    <#
    .SYNOPSIS
        The text of one file in a repository, or $null when it is not there.
    .DESCRIPTION
        A 404 here is a RESULT, not an error. For a dependency graph "the file
        the reference names is not in that repository" is exactly the answer the
        tool exists to give, and throwing would lose it.
    .PARAMETER Organisation
        The Azure DevOps organisation.
    .PARAMETER Project
        The project. All routes are project-scoped -- the accounts and profile
        APIs need a scope a Code+Build read token does not have.
    .PARAMETER RepositoryId
        The repository GUID.
    .PARAMETER Path
        The path within the repository.
    .PARAMETER Ref
        A branch or tag. Defaults to the repository default branch.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Organisation,
        [Parameter(Mandatory)] [string] $Project,
        [Parameter(Mandatory)] [string] $RepositoryId,
        [Parameter(Mandatory)] [string] $Path,
        [string] $Ref
    )

    $query = @{
        'path'           = ('/' + $Path.TrimStart('/'))
        'includeContent' = 'true'
        '$format'        = 'json'
        'api-version'    = '7.1'
    }
    if ($Ref) {
        $query['versionDescriptor.version'] = ($Ref -replace '^refs/heads/', '')
        $query['versionDescriptor.versionType'] = 'branch'
    }

    $item = Invoke-AzDoRestMethod -Uri "https://dev.azure.com/$Organisation/$Project/_apis/git/repositories/$RepositoryId/items" -Query $query -NotFoundIsNull
    if ($null -eq $item) { return $null }

    $record = @($item)[0]
    if ($null -eq $record) { return $null }
    if ($null -eq $record.PSObject.Properties['content']) { return $null }

    [string] $record.content
}
