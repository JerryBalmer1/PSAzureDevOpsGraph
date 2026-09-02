function Resolve-AzDoPipelineReference {
    <#
    .SYNOPSIS
        Resolves one reference to a repository and path, or to an unresolved
        result carrying a reason.
    .DESCRIPTION
        Azure Pipelines resolves a template reference by one of two rules, and
        which rule applies is decided by whether an '@alias' is present:

        * 'path@alias' -- the path is taken from the ROOT of the repository the
          alias names.
        * 'path' -- the path is taken relative to the DIRECTORY of the file that
          made the reference, in that file's own repository.

        Getting this backwards does not usually produce an error. It produces a
        different existing file, which is why the two rules are implemented
        here explicitly rather than by one path join.

        Nothing here touches the network. Existence is decided against the
        inventory the caller supplies, so this command is testable offline.
    .EXAMPLE
        $refs | Resolve-AzDoPipelineReference -SourceRepository pipelines-main -SourcePath pipelines/p01.yml
    #>
    [CmdletBinding()]
    [OutputType('PSAzureDevOpsGraph.ResolvedReference')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Reference,

        # The repository containing the file that made the reference.
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$SourceRepository,

        # The path, within that repository, of the file that made the reference.
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$SourcePath,

        # Alias -> repository name, as declared by resources.repositories in the
        # file that made the reference. Aliases do not cross files.
        [hashtable]$Alias = @{},

        # Repository names that exist. Empty means do not check.
        [string[]]$KnownRepository,

        # Pipeline definition names that exist. Empty means do not check.
        [string[]]$KnownPipeline
    )

    process {
        $kind = $Reference.Kind
        $unresolved = {
            param([string]$Reason, [string]$Repository, [string]$Path)
            [pscustomobject]@{
                PSTypeName       = 'PSAzureDevOpsGraph.ResolvedReference'
                Kind             = $kind
                Reference        = $Reference.Reference
                Alias            = $Reference.Alias
                Resolved         = $false
                TargetKind       = $null
                Repository       = $Repository
                Path             = $Path
                Pipeline         = $null
                Reason           = $Reason
                SourceRepository = $SourceRepository
                SourcePath       = $SourcePath
                Line             = $Reference.Line
            }
        }
        $resolved = {
            param([string]$TargetKind, [string]$Repository, [string]$Path, [string]$Pipeline)
            [pscustomobject]@{
                PSTypeName       = 'PSAzureDevOpsGraph.ResolvedReference'
                Kind             = $kind
                Reference        = $Reference.Reference
                Alias            = $Reference.Alias
                Resolved         = $true
                TargetKind       = $TargetKind
                Repository       = $Repository
                Path             = $Path
                Pipeline         = $Pipeline
                Reason           = $null
                SourceRepository = $SourceRepository
                SourcePath       = $SourcePath
                Line             = $Reference.Line
            }
        }

        switch ($kind) {
            { $_ -in 'template', 'extends' } {
                $refAlias = $Reference.Alias
                if ($refAlias) {
                    if ($refAlias -eq 'self') { $repository = $SourceRepository }
                    elseif ($Alias.ContainsKey($refAlias)) { $repository = $Alias[$refAlias] }
                    else { & $unresolved 'alias-not-declared' $null $Reference.Path; return }
                    # Anchored at the root of the aliased repository.
                    $path = Resolve-AzDoRelativePath -BaseDirectory '' -Path $Reference.Path
                }
                else {
                    $repository = $SourceRepository
                    $directory  = if ($SourcePath -match '/') { $SourcePath -replace '/[^/]*$', '' } else { '' }
                    $path = Resolve-AzDoRelativePath -BaseDirectory $directory -Path $Reference.Path
                }
                if ($KnownRepository -and $repository -notin $KnownRepository) {
                    & $unresolved 'repository-not-found' $repository $path; return
                }
                & $resolved 'yaml' $repository $path $null
            }

            'repositoryResource' {
                # 'name' is 'Project/Repository' or bare 'Repository'.
                $name = $Reference.Name
                $repository = if ($name -match '/') { ($name -split '/')[-1] } else { $name }
                if ($KnownRepository -and $repository -notin $KnownRepository) {
                    & $unresolved 'repository-not-found' $repository $null; return
                }
                & $resolved 'repo' $repository $null $null
            }

            'pipelineResource' {
                $source = $Reference.Source
                if ($KnownPipeline -and $source -notin $KnownPipeline) {
                    & $unresolved 'pipeline-not-found' $null $null; return
                }
                & $resolved 'pipeline' $null $null $source
            }

            'checkout' {
                $value = $Reference.Reference
                if ($value -eq 'none') { return }
                if ($value -eq 'self') { & $resolved 'repo' $SourceRepository $null $null; return }
                if ($value -match '^git://') {
                    $tail = ($value -replace '^git://', '') -replace '@.*$', ''
                    $repository = if ($tail -match '/') { ($tail -split '/')[-1] } else { $tail }
                }
                elseif ($Alias.ContainsKey($value)) { $repository = $Alias[$value] }
                else { & $unresolved 'alias-not-declared' $null $null; return }
                if ($KnownRepository -and $repository -notin $KnownRepository) {
                    & $unresolved 'repository-not-found' $repository $null; return
                }
                & $resolved 'repo' $repository $null $null
            }

            default { & $unresolved "unsupported-reference-kind" $null $null }
        }
    }
}
