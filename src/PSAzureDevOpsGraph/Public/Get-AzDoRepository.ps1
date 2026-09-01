function Get-AzDoRepository {
    <#
    .SYNOPSIS
        The Git repositories in an Azure DevOps project.
    .DESCRIPTION
        Used to look files up. It is deliberately NOT the source of repository
        nodes in the dependency graph: a repository nothing references is not a
        dependency of anything, and a graph that includes it answers "what is in
        this project" rather than "what do these pipelines depend on".
    .PARAMETER Organisation
        The Azure DevOps organisation. An input, never discovered - the accounts
        and profile APIs need a scope a Code+Build read token does not have and
        answer 401.
    .PARAMETER Project
        The project within the organisation.
    .PARAMETER Name
        Return only the repository with this name.
    .EXAMPLE
        Get-AzDoRepository -Organisation jlbalmerjr1 -Project ClaudeTesting

        Lists every Git repository in the project.
    .OUTPUTS
        PSAzureDevOpsGraph.Repository
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)] [ValidateNotNullOrEmpty()] [string] $Organisation,
        [Parameter(Mandatory, Position = 1)] [ValidateNotNullOrEmpty()] [string] $Project,
        [string] $Name
    )

    process {
        $uri = "https://dev.azure.com/$Organisation/$Project/_apis/git/repositories"
        $repositories = Invoke-AzDoRestMethod -Uri $uri -Query @{ 'api-version' = '7.1' }

        foreach ($repository in $repositories) {
            if ($Name -and $repository.name -cne $Name) { continue }
            [pscustomobject] @{
                PSTypeName    = 'PSAzureDevOpsGraph.Repository'
                Id            = $repository.id
                Name          = $repository.name
                DefaultBranch = $repository.defaultBranch
                Organisation  = $Organisation
                Project       = $Project
            }
        }
    }
}
