function Get-AzDoRepository {
    <#
    .SYNOPSIS
        The Git repositories in an Azure DevOps project.
    .DESCRIPTION
        Read-only. Returns every repository in the project, including ones with
        no pipelines and ones with no commits: an empty repository is a fact
        about the project, and dropping it would make a project that has one
        indistinguishable from a project that does not.
    .EXAMPLE
        Get-AzDoRepository -Organisation jlbalmerjr1 -Project ClaudeTesting
    #>
    [CmdletBinding()]
    [OutputType('PSAzureDevOpsGraph.Repository')]
    param(
        [Parameter(Mandatory)][string]$Organisation,
        [Parameter(Mandatory)][string]$Project,
        # Filter by repository name. Wildcards are accepted.
        [string]$Name
    )

    $response = Invoke-AzDoRestMethod -ApiPath 'git/repositories' -Organisation $Organisation -Project $Project
    foreach ($repo in $response.value) {
        if ($Name -and $repo.name -notlike $Name) { continue }

        # A repository with no commits has no defaultBranch property at all --
        # not a null one. Reading it directly would throw under StrictMode and
        # silently drop exactly the repository this command must still report.
        $property = { param($n) if ($repo.PSObject.Properties[$n]) { $repo.PSObject.Properties[$n].Value } else { $null } }
        $defaultBranch = & $property 'defaultBranch'

        [pscustomobject]@{
            PSTypeName    = 'PSAzureDevOpsGraph.Repository'
            Id            = $repo.id
            Name          = $repo.name
            Project       = $Project
            Organisation  = $Organisation
            DefaultBranch = $defaultBranch
            IsEmpty       = [string]::IsNullOrEmpty($defaultBranch)
            Size          = & $property 'size'
            WebUrl        = & $property 'webUrl'
        }
    }
}
