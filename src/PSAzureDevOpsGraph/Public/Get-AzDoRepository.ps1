function Get-AzDoRepository {
    <#
    .SYNOPSIS
        The Git repositories in an Azure DevOps project.
    .DESCRIPTION
        A lookup table, not a source of graph nodes. The dependency graph uses
        this to find files and to turn a repository name into the id the items
        route needs; it does not turn the result into nodes, because a
        repository nothing references is not part of what these pipelines depend
        on. A graph built from this endpoint answers "what is in this project"
        rather than "what do these pipelines depend on", and only the second
        question makes "if I change this template, which pipelines break"
        answerable.
    .PARAMETER Organisation
        The Azure DevOps organisation. Not discovered: the accounts and profile
        APIs need vso.profile scope, which a Code+Build read token does not
        have, and they answer 401.
    .PARAMETER Project
        The project. Every route this module calls is project-scoped.
    .PARAMETER Name
        Return only the repository with this name. Matching is case-insensitive,
        as Azure DevOps repository names are.
    .EXAMPLE
        # Needs $env:AZDO_PAT with Code (Read) and Build (Read).
        Get-AzDoRepository -Organisation jlbalmerjr1 -Project ClaudeTesting

        Lists every repository in the project, with its id and default branch.
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

    $uri = "https://dev.azure.com/$Organisation/$Project/_apis/git/repositories"
    $result = Invoke-AzDoRestMethod -Uri $uri -Query @{ 'api-version' = '7.1' }

    foreach ($repository in @($result)) {
        if ($null -eq $repository) { continue }
        if ($Name -and $repository.name -ne $Name) { continue }

        [pscustomobject]@{
            PSTypeName    = 'PSAzureDevOpsGraph.Repository'
            Id            = [string] $repository.id
            Name          = [string] $repository.name
            Project       = $Project
            DefaultBranch = [string] $repository.defaultBranch
            WebUrl        = [string] $repository.webUrl
            IsDisabled    = [bool] $repository.isDisabled
        }
    }
}
