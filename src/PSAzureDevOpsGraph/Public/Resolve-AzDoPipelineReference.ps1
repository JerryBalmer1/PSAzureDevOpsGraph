function Resolve-AzDoPipelineReference {
    <#
    .SYNOPSIS
        Where one reference points, or why it does not resolve.
    .DESCRIPTION
        The two resolution rules produce different files from the same text.

        With no @alias the path is relative to the DIRECTORY OF THE FILE making
        the reference. With an @alias the path is joined to the ROOT of the
        repository the alias names, and the alias is looked up in the
        resources.repositories of the file making the reference - not of the
        pipeline that started the traversal.

        The current repository is a property of the file, not of the traversal.
        Carrying one "current repo" for a whole walk resolves a relative
        reference inside a cross-repo template back into the repository the
        pipeline started in, and returns a real file that is the wrong one.

        A reference that does not resolve comes back as a result carrying a
        reason, never as an error and never dropped. A broken pipeline that
        vanishes from the output looks identical to a clean one.

        The reason is 'token: explanation'. The token is the machine half - the
        two are kept distinct because they need different fixes - and the
        explanation names the file, the alias or the path that has to change, so
        a reader does not have to open the graph to find out what to do.
    .PARAMETER Reference
        One reference record from Get-AzDoPipelineReference.
    .PARAMETER SourceRepository
        The repository holding the file that made the reference.
    .PARAMETER SourcePath
        The path, within that repository, of the file that made the reference.
    .PARAMETER Alias
        The aliases that file declares: alias name to repository name.
    .PARAMETER TestFile
        A predicate taking a repository name and a path, returning whether that
        file exists. Supply it to have a missing file come back as
        file-not-found; omit it to resolve without asking the world anything.
    .EXAMPLE
        $reference | Resolve-AzDoPipelineReference -SourceRepository consumer-app -SourcePath azure-pipelines.yml -Alias @{ mainPipelines = 'pipelines-main' }

        Resolves templates/steps-build.yml@mainPipelines to pipelines-main at its repository root.
    .OUTPUTS
        PSAzureDevOpsGraph.ResolvedReference
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)] [ValidateNotNull()] [psobject] $Reference,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $SourceRepository,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $SourcePath,
        [AllowEmptyCollection()] [hashtable] $Alias = @{},
        [scriptblock] $TestFile
    )

    process {
        $resolved = $true
        $reason = $null
        $repository = $null
        $path = $null
        $targetKind = 'yaml'

        switch ($Reference.Kind) {

            { $_ -in 'template', 'extends' } {
                if ($Reference.Alias) {
                    if ($Alias.ContainsKey($Reference.Alias)) {
                        $repository = [string] $Alias[$Reference.Alias]
                        # From the ROOT of the aliased repository.
                        $path = Join-AzDoRepoPath -BasePath '' -Reference $Reference.Path
                    } else {
                        $resolved = $false
                        $reason = "alias-not-declared: '$($Reference.Alias)' is not in resources.repositories of $SourcePath, so the repository is unknown and the path cannot be resolved at all"
                    }
                } else {
                    $repository = $SourceRepository
                    $path = Join-AzDoRepoPath -BasePath $SourcePath -Reference $Reference.Path
                }

                if ($resolved -and $TestFile -and -not (& $TestFile $repository $path)) {
                    $resolved = $false
                    $reason = "file-not-found: resolved to $path in $repository, which does not exist"
                }
                break
            }

            'repositoryResource' {
                $targetKind = 'repo'
                $repository = [string] $Reference.Repository
                break
            }

            'checkout' {
                $targetKind = 'repo'
                if ($Alias.ContainsKey($Reference.Alias)) {
                    $repository = [string] $Alias[$Reference.Alias]
                } else {
                    $resolved = $false
                    $reason = "alias-not-declared: '$($Reference.Alias)' is not in resources.repositories of $SourcePath, so the repository is unknown and the path cannot be resolved at all"
                }
                break
            }

            'pipelineResource' {
                $targetKind = 'pipeline'
                break
            }
        }

        # An unresolved target must not collide with a real node. Keeping the
        # alias in the id is what makes that impossible, and it says which alias
        # was missing without guessing a repository.
        $targetId = if (-not $resolved -and $reason -like 'alias-not-declared*') {
            if ($targetKind -eq 'repo') { "repo:@$($Reference.Alias)" }
            else { "yaml:@$($Reference.Alias)/$($Reference.Path)" }
        } elseif ($targetKind -eq 'repo') {
            "repo:$repository"
        } elseif ($targetKind -eq 'pipeline') {
            "pipeline:$($Reference.Reference)"
        } else {
            "yaml:$repository/$path"
        }

        [pscustomobject] @{
            PSTypeName = 'PSAzureDevOpsGraph.ResolvedReference'
            Kind       = $Reference.Kind
            Reference  = $Reference.Reference
            Alias      = $Reference.Alias
            Resolved   = $resolved
            Reason     = $reason
            TargetKind = $targetKind
            Repository = $repository
            Path       = $path
            TargetId   = $targetId
        }
    }
}
