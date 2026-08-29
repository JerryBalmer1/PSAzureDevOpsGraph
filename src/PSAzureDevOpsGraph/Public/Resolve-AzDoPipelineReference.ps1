function Resolve-AzDoPipelineReference {
    <#
        .SYNOPSIS
            Resolves one reference to a repository and path, or to an
            unresolved result carrying a reason.

        .DESCRIPTION
            Two rules, and they produce different files from the same text.

            Without an @alias, the path is relative to the DIRECTORY OF THE
            FILE that made the reference - not to the root of the repository. A
            repository can hold both templates/steps-build.yml and
            pipelines/templates/steps-build.yml, and a root-relative resolver
            does not error: it returns the wrong file, confidently.

            With an @alias, the path is joined to the ROOT of the repository the
            alias names, and the alias is looked up in the resources.repositories
            of the file making the reference.

            The including repository is a property of the file, not of the
            traversal. A relative reference inside a cross-repo template stays
            in that template's repository.

        .PARAMETER Reference
            A reference object from Get-AzDoPipelineReference.

        .PARAMETER FromRepository
            The repository containing the file that made the reference.

        .PARAMETER FromPath
            The repository-relative path of the file that made the reference.

        .PARAMETER Alias
            The alias-to-repository map declared by that same file.

        .EXAMPLE
            Resolve-AzDoPipelineReference -Reference $ref -FromRepository pipelines-main `
                -FromPath pipelines/p01.yml -Alias @{}

            Resolves 'templates/steps-build.yml' to
            pipelines/templates/steps-build.yml, relative to the including file.

        .EXAMPLE
            Resolve-AzDoPipelineReference -Reference $ref -FromRepository consumer-app `
                -FromPath azure-pipelines.yml -Alias @{ mainPipelines = 'pipelines-main' }

            Resolves 'templates/steps-build.yml@mainPipelines' from the root of
            pipelines-main.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Reference,
        [Parameter(Mandatory)] [string] $FromRepository,
        [Parameter(Mandatory)] [string] $FromPath,
        [hashtable] $Alias = @{}
    )

    if ($Reference.RefKind -notin @('template', 'extends')) {
        return [pscustomobject]@{
            Resolved   = $true
            Repository = $null
            Path       = $null
            Reason     = $null
            Detail     = $null
            Reference  = $Reference
        }
    }

    if ($Reference.Alias) {
        if (-not $Alias.ContainsKey($Reference.Alias)) {
            # The alias was never declared in this file's
            # resources.repositories. A different fix from a missing file, so a
            # different reason.
            return [pscustomobject]@{
                Resolved   = $false
                Repository = $null
                Path       = $Reference.Path
                Reason     = 'alias-not-declared'
                Detail     = ("'{0}' is not in resources.repositories of {1}, so the repository is unknown and the path cannot be resolved at all" -f $Reference.Alias, $FromPath)
                Reference  = $Reference
            }
        }

        return [pscustomobject]@{
            Resolved   = $true
            Repository = $Alias[$Reference.Alias]
            Path       = Resolve-AzDoRepositoryPath -Path $Reference.Path
            Reason     = $null
            Detail     = $null
            Reference  = $Reference
        }
    }

    $directory = ($FromPath -replace '\\', '/')
    $directory = if ($directory -match '/') { $directory -replace '/[^/]+$', '' } else { '' }

    [pscustomobject]@{
        Resolved   = $true
        Repository = $FromRepository
        Path       = Resolve-AzDoRepositoryPath -Path ("$directory/$($Reference.Path)")
        Reason     = $null
        Detail     = $null
        Reference  = $Reference
    }
}
