function Resolve-AzDoPipelineReference {
    <#
    .SYNOPSIS
        Where one reference points: a repository and a path, or an unresolved
        result carrying a reason.
    .DESCRIPTION
        Takes one reference, the file that made it, and that file's declared
        aliases. The two resolution rules produce different files from the same
        text:

        - No @alias: relative to the DIRECTORY OF THE INCLUDING FILE, not to the
          root of its repository. A repository can hold both
          templates/steps-build.yml and pipelines/templates/steps-build.yml, and
          a root-relative resolver does not error - it returns the wrong file,
          confidently.
        - With @alias: from the ROOT of the aliased repository, where the alias
          is looked up in the resources.repositories of the file making the
          reference.

        The current repository is a property of the FILE, not of the traversal.
        SourceRepository is therefore a parameter per call: carrying one value
        for a whole walk resolves a relative reference inside a cross-repository
        template back into the repository the pipeline started in.

        An unresolved reference is a result, never a dropped edge. A broken
        pipeline that vanishes from the output looks identical to a clean one,
        which is the one case the tool exists to report. The two reasons are
        kept distinct because they need different fixes: file-not-found means
        add the file, alias-not-declared means add the resources.repositories
        entry.
    .PARAMETER Reference
        A reference record from Get-AzDoPipelineReference.
    .PARAMETER SourceRepository
        The repository holding the file that made the reference.
    .PARAMETER SourcePath
        The path, within that repository, of the file that made the reference.
    .PARAMETER Alias
        The aliases the referencing file declares, as alias name to repository
        name. Usually built from that file's own repositoryResource references.
    .PARAMETER TestFile
        A predicate taking a repository name and a path and returning whether
        that file exists. Omit it to resolve structurally, without deciding
        whether the target is there.
    .PARAMETER KnownRepository
        The repository names that exist. A reference to anything else resolves
        to repository-not-found rather than to a node nothing can back.
    .PARAMETER KnownPipeline
        The pipeline definition names that exist, for resources.pipelines.
    .EXAMPLE
        $ref = Get-AzDoPipelineReference -Content "steps:`n  - template: templates/build.yml`n"
        Resolve-AzDoPipelineReference -Reference $ref -SourceRepository app -SourcePath pipelines/p01.yml

        Resolves relative to pipelines/, giving app / pipelines/templates/build.yml.
    .OUTPUTS
        PSAzureDevOpsGraph.Resolution
    #>
    [CmdletBinding()]
    [OutputType('PSAzureDevOpsGraph.Resolution')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('PSAzureDevOpsGraph.Reference')] $Reference,

        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $SourceRepository,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $SourcePath,

        [System.Collections.IDictionary] $Alias = @{},
        [scriptblock] $TestFile,
        [AllowEmptyCollection()] [string[]] $KnownRepository = @(),
        [AllowEmptyCollection()] [string[]] $KnownPipeline = @()
    )

    process {
        $sourceDirectory = ($SourcePath -replace '\\', '/')
        $slash = $sourceDirectory.LastIndexOf('/')
        $sourceDirectory = if ($slash -ge 0) { $sourceDirectory.Substring(0, $slash) } else { '' }

        $state = [ordered]@{
            PSTypeName = 'PSAzureDevOpsGraph.Resolution'
            Reference  = $Reference.Reference
            Kind       = $Reference.Kind
            Alias      = $Reference.Alias
            Resolved   = $false
            TargetKind = $null
            Repository = $null
            Path       = $null
            TargetId   = $null
            Reason     = $null
        }

        switch ($Reference.Kind) {
            { $_ -in 'template', 'extends' } {
                $state['TargetKind'] = 'yaml'
                if ($Reference.Alias) {
                    if (-not $Alias.Contains($Reference.Alias)) {
                        # Keep the alias in the id so the pseudo-node cannot be
                        # mistaken for a real one, and so the reader can see
                        # which alias was never declared.
                        $state['TargetId'] = "yaml:@$($Reference.Alias)/$($Reference.Path)"
                        $state['Reason'] = "alias-not-declared: '$($Reference.Alias)' is not in resources.repositories of $SourcePath, so the repository is unknown and the path cannot be resolved at all"
                        break
                    }
                    $repository = [string] $Alias[$Reference.Alias]
                    $path = Resolve-AzDoRepositoryPath -SourceDirectory '' -Reference $Reference.Path -FromRepositoryRoot
                } else {
                    $repository = $SourceRepository
                    $path = Resolve-AzDoRepositoryPath -SourceDirectory $sourceDirectory -Reference $Reference.Path
                }

                $state['Repository'] = $repository
                $state['Path'] = $path
                $state['TargetId'] = "yaml:$repository/$path"

                if ($KnownRepository.Count -and $repository -notin $KnownRepository) {
                    $state['Reason'] = "repository-not-found: '$repository' is not a repository in this project"
                    break
                }
                if ($TestFile -and -not (& $TestFile $repository $path)) {
                    # The reason names the RESOLVED path and repository, not the
                    # reference text. Which of the two resolution rules ran is
                    # the thing a reader cannot reconstruct, and it is what
                    # makes "add the file" actionable.
                    $state['Reason'] = "file-not-found: resolved to $path in $repository, which does not exist"
                    break
                }
                $state['Resolved'] = $true
            }

            'repositoryResource' {
                # name may be project-qualified as project/repository.
                $repository = [string] $Reference.Name
                $slashAt = $repository.LastIndexOf('/')
                if ($slashAt -ge 0) { $repository = $repository.Substring($slashAt + 1) }

                $state['TargetKind'] = 'repo'
                $state['Repository'] = $repository
                $state['TargetId'] = "repo:$repository"

                if ($Reference.Type -and $Reference.Type -notin 'git', 'azureRepo', 'azureRepos') {
                    $state['Reason'] = "repository-not-found: '$repository' is declared as type '$($Reference.Type)', which is not a repository in this project"
                    break
                }
                if ($KnownRepository.Count -and $repository -notin $KnownRepository) {
                    $state['Reason'] = "repository-not-found: '$repository' is named by resources.repositories of $SourcePath but is not a repository in this project"
                    break
                }
                $state['Resolved'] = $true
            }

            'checkout' {
                $state['TargetKind'] = 'repo'
                if (-not $Alias.Contains($Reference.Alias)) {
                    $state['TargetId'] = "repo:@$($Reference.Alias)"
                    $state['Reason'] = "alias-not-declared: '$($Reference.Alias)' is checked out by $SourcePath but is not in its resources.repositories, so the repository is unknown"
                    break
                }
                $repository = [string] $Alias[$Reference.Alias]
                $state['Repository'] = $repository
                $state['TargetId'] = "repo:$repository"

                if ($KnownRepository.Count -and $repository -notin $KnownRepository) {
                    $state['Reason'] = "repository-not-found: alias '$($Reference.Alias)' names '$repository', which is not a repository in this project"
                    break
                }
                $state['Resolved'] = $true
            }

            'pipelineResource' {
                # source: names a pipeline DEFINITION, not a file.
                $state['TargetKind'] = 'pipeline'
                $state['TargetId'] = "pipeline:$($Reference.Name)"
                if ($KnownPipeline.Count -and $Reference.Name -notin $KnownPipeline) {
                    $state['Reason'] = "pipeline-not-found: no definition named '$($Reference.Name)' in this project"
                    break
                }
                $state['Resolved'] = $true
            }
        }

        [pscustomobject] $state
    }
}
