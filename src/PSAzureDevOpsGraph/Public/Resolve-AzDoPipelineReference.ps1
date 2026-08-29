Set-StrictMode -Version 3.0

function Resolve-AzDoPipelineReference {
    <#
    .SYNOPSIS
        Turn one reference into a repository and a path, or into an unresolved
        result carrying a reason.

    .DESCRIPTION
        Takes a reference from Get-AzDoPipelineReference, the file that made it,
        and that file's declared aliases, and works out what it points at.

        The two anchoring rules are the substance:

        * No alias -- the path is relative to the DIRECTORY OF THE REFERRING
          FILE, within that file's own repository. A leading '/' overrides this
          and anchors at the repository root.
        * With an alias -- the path is anchored at the ROOT of the aliased
          repository. Never relative to the referrer.

        Failure is a result, not an exception. An unresolved reference returns
        Resolved = $false and a Reason, because a broken reference is the one
        the user most wants to see, and a reference that throws or vanishes
        looks exactly like one that was fine.

    .PARAMETER Reference
        A reference object from Get-AzDoPipelineReference.

    .PARAMETER SourceRepository
        Name of the repository holding the file that made the reference.

    .PARAMETER SourcePath
        Path, within that repository, of the file that made the reference.

    .PARAMETER AliasMap
        Alias -> repository declaration, from the referring file's
        resources.repositories. Keys are the alias names.

    .PARAMETER Repository
        The repositories in the project, from Get-AzDoRepository.

    .PARAMETER Pipeline
        The pipeline definitions in the project, from Get-AzDoPipeline. Needed
        only to resolve pipeline resources.

    .PARAMETER Inventory
        Repository name -> the set of paths it contains. When supplied, a
        reference to a path that does not exist resolves to a reason rather
        than to a phantom node.

    .EXAMPLE
        $refs | Resolve-AzDoPipelineReference -SourceRepository pipelines-main `
                    -SourcePath pipelines/p01.yml -AliasMap $aliases `
                    -Repository $repos -Inventory $inventory
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [pscustomobject] $Reference,

        [Parameter(Mandatory)][string] $SourceRepository,
        [Parameter(Mandatory)][AllowEmptyString()][string] $SourcePath,

        [Parameter()][hashtable] $AliasMap = @{},
        [Parameter()][object[]] $Repository = @(),
        [Parameter()][object[]] $Pipeline = @(),
        [Parameter()][hashtable] $Inventory = @{},
        [Parameter()][string] $Project
    )

    begin {
        $repoByName = @{}
        foreach ($r in $Repository) { $repoByName[$r.Name] = $r }
    }

    process {
        $result = [ordered]@{
            Kind             = $Reference.Kind
            Reference        = $Reference.Reference
            Alias            = $Reference.Alias
            SourceRepository = $SourceRepository
            SourcePath       = $SourcePath
            Resolved         = $false
            TargetKind       = $null
            TargetRepository = $null
            TargetPath       = $null
            TargetPipeline   = $null
            Reason           = $null
        }

        switch ($Reference.Kind) {

            { $_ -in @('template', 'extends') } {
                $split = Split-AzDoTemplateReference -Reference ([string]$Reference.Reference)
                $targetRepo = $null

                if ([string]::IsNullOrEmpty($split.Alias)) {
                    # Relative to the referring file's directory, same repository.
                    $targetRepo = $SourceRepository
                    $targetPath = Join-AzDoRepositoryPath -BaseDirectory (Get-AzDoParentPath -Path $SourcePath) `
                                                          -ReferencePath $split.Path
                }
                elseif ($split.Alias -eq 'self') {
                    $targetRepo = $SourceRepository
                    $targetPath = Join-AzDoRepositoryPath -BaseDirectory '' -ReferencePath $split.Path
                }
                elseif ($AliasMap.ContainsKey($split.Alias)) {
                    $decl = $AliasMap[$split.Alias]

                    if ($decl.Type -and $decl.Type -ne 'git') {
                        $result.Reason = "repository resource '$($split.Alias)' is of type '$($decl.Type)'; only Azure Repos Git repositories are read"
                        break
                    }
                    if ($decl.Project -and $Project -and $decl.Project -ne $Project) {
                        $result.Reason = "repository resource '$($split.Alias)' names project '$($decl.Project)', which is not '$Project'"
                        break
                    }
                    if (-not $repoByName.ContainsKey($decl.Repository)) {
                        $result.Reason = "repository '$($decl.Repository)', aliased '$($split.Alias)', does not exist in project '$Project'"
                        break
                    }

                    $targetRepo = $decl.Repository
                    $targetPath = Join-AzDoRepositoryPath -BaseDirectory '' -ReferencePath $split.Path
                }
                else {
                    $result.Reason = "alias '$($split.Alias)' is not declared in resources.repositories"
                    break
                }

                if (-not (Test-AzDoInventoryPath -Inventory $Inventory -RepositoryName $targetRepo -Path $targetPath)) {
                    $result.Reason = "file '$targetPath' does not exist in repository '$targetRepo'"
                    break
                }

                $result.Resolved         = $true
                $result.TargetKind       = 'yaml'
                $result.TargetRepository = $targetRepo
                $result.TargetPath       = $targetPath
                break
            }

            'repositoryResource' {
                $declaredName = [string]$Reference.RepositoryName
                $short        = Get-AzDoShortRepositoryName -Name $declaredName
                $inProject    = Get-AzDoRepositoryProjectName -Name $declaredName
                $type         = [string]$Reference.ResourceType

                if ($type -and $type -ne 'git') {
                    $result.Reason = "repository resource '$($Reference.Alias)' is of type '$type'; only Azure Repos Git repositories are read"
                    break
                }
                if ($inProject -and $Project -and $inProject -ne $Project) {
                    $result.Reason = "repository resource '$($Reference.Alias)' names project '$inProject', which is not '$Project'"
                    break
                }
                if (-not $repoByName.ContainsKey($short)) {
                    $result.Reason = "repository '$short', aliased '$($Reference.Alias)', does not exist in project '$Project'"
                    break
                }

                $result.Resolved         = $true
                $result.TargetKind       = 'repo'
                $result.TargetRepository = $short
                break
            }

            'pipelineResource' {
                $source = [string]$Reference.Source
                $match  = @($Pipeline | Where-Object { $_.Name -eq $source })

                if ($match.Count -eq 0) {
                    $result.Reason = "no pipeline definition named '$source' exists in project '$Project'"
                    break
                }

                $result.Resolved       = $true
                $result.TargetKind     = 'pipeline'
                $result.TargetPipeline = $match[0].Name
                break
            }

            'checkout' {
                $value = [string]$Reference.Reference

                if ($value -eq 'none') {
                    # Not a dependency: an instruction not to fetch sources.
                    $result.Resolved   = $true
                    $result.TargetKind = 'none'
                    break
                }

                if ($value -eq 'self') {
                    $result.Resolved         = $true
                    $result.TargetKind       = 'repo'
                    $result.TargetRepository = $SourceRepository
                    break
                }

                if ($AliasMap.ContainsKey($value)) {
                    $decl = $AliasMap[$value]
                    if (-not $repoByName.ContainsKey($decl.Repository)) {
                        $result.Reason = "repository '$($decl.Repository)', aliased '$value', does not exist in project '$Project'"
                        break
                    }
                    $result.Resolved         = $true
                    $result.TargetKind       = 'repo'
                    $result.TargetRepository = $decl.Repository
                    break
                }

                $result.Reason = "alias '$value' is not declared in resources.repositories"
                break
            }

            default {
                $result.Reason = "reference kind '$($Reference.Kind)' is not understood"
            }
        }

        [pscustomobject]$result
    }
}
