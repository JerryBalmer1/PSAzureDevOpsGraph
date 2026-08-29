function Get-AzDoPipelineYaml {
    <#
        .SYNOPSIS
            Returns the YAML text of a path in a repository, or $null if absent.

        .DESCRIPTION
            Absence is a result, not an error: an unresolved reference with
            reason file-not-found is exactly what the graph must report, so a
            missing file returns $null rather than throwing.

        .PARAMETER Organisation
            The Azure DevOps organisation name.

        .PARAMETER Project
            The project name.

        .PARAMETER RepositoryId
            The repository id or name the file lives in.

        .PARAMETER Path
            The repository-relative path of the file.

        .EXAMPLE
            Get-AzDoPipelineYaml -Organisation contoso -Project ClaudeTesting `
                                 -RepositoryId pipelines-main -Path pipelines/p01.yml

            Returns the text of p01.yml, or $null if it does not exist.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Organisation,
        [Parameter(Mandatory)] [string] $Project,
        [Parameter(Mandatory)] [string] $RepositoryId,
        [Parameter(Mandatory)] [string] $Path
    )

    Get-AzDoItemContent -Organisation $Organisation -Project $Project -RepositoryId $RepositoryId -Path $Path
}
