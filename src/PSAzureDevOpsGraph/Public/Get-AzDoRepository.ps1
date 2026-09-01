function Get-AzDoRepository {
    <#
    .SYNOPSIS
        The Git repositories in an Azure DevOps project.
    .DESCRIPTION
        A flat list of the project's repositories, used to look files up by name.

        Note what this is NOT for: the dependency graph does not turn this list
        into nodes. A repository nothing references is not part of the answer to
        "what do these pipelines depend on", and including it answers the
        different question "what is in this project".
    .PARAMETER Organisation
        The Azure DevOps organisation. An input, never discovered -- the accounts
        API needs vso.profile scope, which a Code+Build read token does not have.
    .PARAMETER Project
        The project name.
    .PARAMETER Name
        Return only the repository with this name.
    .EXAMPLE
        # Needs $env:AZDO_PAT with Code (Read) and Build (Read).
        Get-AzDoRepository -Organisation jlbalmerjr1 -Project ClaudeTesting

        Lists every repository in the project with its id and default branch.
    .OUTPUTS
        PSAzureDevOpsGraph.Repository
    #>
    [CmdletBinding()]
    [OutputType('PSAzureDevOpsGraph.Repository')]
    param(
        [Parameter(Mandatory, Position = 0)] [ValidateNotNullOrEmpty()] [string] $Organisation,
        [Parameter(Mandatory, Position = 1)] [ValidateNotNullOrEmpty()] [string] $Project,
        [string] $Name
    )

    process {
        $repositories = Invoke-AzDoRestMethod -Uri "https://dev.azure.com/$Organisation/$Project/_apis/git/repositories" -Query @{ 'api-version' = '7.1' }

        foreach ($repository in $repositories) {
            if ($Name -and $repository.name -ne $Name) { continue }

            [pscustomobject]@{
                PSTypeName    = 'PSAzureDevOpsGraph.Repository'
                Name          = $repository.name
                Id            = $repository.id
                DefaultBranch = $repository.defaultBranch
                Organisation  = $Organisation
                Project       = $Project
            }
        }
    }
}
