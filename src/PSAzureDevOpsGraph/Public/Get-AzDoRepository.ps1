function Get-AzDoRepository {
    <#
        .SYNOPSIS
            Lists the Git repositories in an Azure DevOps project.

        .DESCRIPTION
            Read-only. Used to look files up by repository id; the dependency
            graph does NOT turn this list into nodes. A project has
            repositories no pipeline touches, and a graph containing them
            answers "what is in this project" rather than "what do these
            pipelines depend on".

        .PARAMETER Organisation
            The Azure DevOps organisation name.

        .PARAMETER Project
            The project name.

        .EXAMPLE
            Get-AzDoRepository -Organisation contoso -Project ClaudeTesting

            Lists every repository in the project.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Organisation,
        [Parameter(Mandatory)] [string] $Project
    )

    $uri = 'https://dev.azure.com/{0}/{1}/_apis/git/repositories' -f $Organisation, $Project

    foreach ($repo in (Invoke-AzDoRestMethod -Uri $uri -Query @{ 'api-version' = '7.1' })) {
        [pscustomobject]@{
            Name          = $repo.name
            Id            = $repo.id
            DefaultBranch = $repo.defaultBranch
            Project       = $Project
            Organisation  = $Organisation
        }
    }
}
