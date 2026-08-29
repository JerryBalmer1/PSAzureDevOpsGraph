Set-StrictMode -Version 3.0

function Get-AzDoRepository {
    <#
    .SYNOPSIS
        The Git repositories in an Azure DevOps project.

    .DESCRIPTION
        Read-only. Returns one object per repository, including repositories
        that are empty.

        An empty repository has no default branch, and the REST payload omits
        the property rather than returning null. It is reported here with
        IsEmpty = $true and DefaultBranch = $null, because a repository that
        exists and holds nothing is a fact about the project, and dropping it
        would make an empty repository indistinguishable from an absent one.

    .PARAMETER Organisation
        The Azure DevOps organisation name.

    .PARAMETER Project
        The project name. Every route this module uses is project scoped.

    .PARAMETER Name
        Return only the repository with this name.

    .EXAMPLE
        Get-AzDoRepository -Organisation contoso -Project Platform
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Organisation,
        [Parameter(Mandatory)][string] $Project,
        [Parameter()][string] $Name
    )

    $response = Invoke-AzDoRestMethod -Organisation $Organisation -Project $Project -Resource 'git/repositories'

    foreach ($repo in $response.value) {
        if ($Name -and $repo.name -ne $Name) { continue }

        $hasDefault = ($repo.PSObject.Properties.Name -contains 'defaultBranch') -and
                      -not [string]::IsNullOrWhiteSpace($repo.defaultBranch)

        [pscustomobject]@{
            PSTypeName    = 'PSAzureDevOpsGraph.Repository'
            Id            = $repo.id
            Name          = $repo.name
            Project       = $Project
            Organisation  = $Organisation
            DefaultBranch = if ($hasDefault) { $repo.defaultBranch } else { $null }
            IsEmpty       = -not $hasDefault
            WebUrl        = if ($repo.PSObject.Properties.Name -contains 'webUrl') { $repo.webUrl } else { $null }
        }
    }
}
