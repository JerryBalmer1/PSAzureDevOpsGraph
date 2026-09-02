function Resolve-AzDoPipelineReference {
    <#
    .SYNOPSIS
        Where one reference points, or why it does not point anywhere.
    .DESCRIPTION
        Takes one reference, the file that made it, and that file's declared
        aliases, and returns a repository and path -- or an unresolved result
        carrying a reason.

        The two rules produce different files from the same text:

        NO @alias -- relative to the DIRECTORY OF THE FILE making the reference,
        not to the root of its repository. A repository can hold both
        templates/steps-build.yml and pipelines/templates/steps-build.yml, and a
        root-relative resolver does not error: it returns the wrong file,
        confidently.

        WITH @alias -- from the ROOT of the aliased repository, where the alias
        is looked up in the resources.repositories of THE FILE MAKING THE
        REFERENCE.

        The current repository is a property of the file, not of the traversal. A
        relative reference inside a cross-repo template stays in that template's
        repository; carrying one "current repo" through a whole walk resolves it
        back into the repository the pipeline started in.

        The two unresolved reasons are kept distinct because they need different
        fixes: alias-not-declared wants a resources.repositories entry,
        file-not-found wants the file.
    .PARAMETER Reference
        A reference from Get-AzDoPipelineReference.
    .PARAMETER SourceRepository
        The repository holding the file that made the reference.
    .PARAMETER SourcePath
        The path, within that repository, of the file that made the reference.
    .PARAMETER Alias
        The aliases that file declares: alias name to repository name. Anything
        not in here is alias-not-declared, whatever other files may declare.
    .PARAMETER KnownPath
        Repository-qualified paths ("repo/path") known to exist. Supply it and
        the result can say file-not-found; omit it and existence is simply not
        asserted, which is what lets this be tested with no credentials.
    .EXAMPLE
        $ref = Get-AzDoPipelineReference -Yaml 'steps: [ { template: templates/steps-build.yml } ]'
        Resolve-AzDoPipelineReference -Reference $ref -SourceRepository pipelines-main -SourcePath pipelines/p01.yml

        Resolves relative to pipelines/, giving pipelines/templates/steps-build.yml.
    .OUTPUTS
        PSAzureDevOpsGraph.Resolution
    #>
    [CmdletBinding()]
    [OutputType('PSAzureDevOpsGraph.Resolution')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [PSTypeName('PSAzureDevOpsGraph.Reference')] $Reference,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $SourceRepository,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $SourcePath,
        [AllowNull()] [hashtable] $Alias = @{},
        [AllowEmptyCollection()] [string[]] $KnownPath = @()
    )

    begin {
        # Azure DevOps matches item paths case-insensitively, so existence is
        # tested that way; but the CANONICAL casing from the repository is what
        # is returned, so a node id never varies with how a reference was typed.
        $canonical = @{}
        foreach ($known in $KnownPath) {
            if ($known) { $canonical[$known.ToLowerInvariant()] = $known }
        }
        $checkExistence = $KnownPath.Count -gt 0
    }

    process {
        $aliases = if ($null -eq $Alias) { @{} } else { $Alias }

        $result = [ordered]@{
            PSTypeName  = 'PSAzureDevOpsGraph.Resolution'
            Reference   = $Reference
            RefKind     = $Reference.RefKind
            Ref         = $Reference.Ref
            Alias       = $Reference.Alias
            Resolved    = $false
            TargetKind  = $null
            Repository  = $null
            Path        = $null
            Name        = $null
            Reason      = $null
            ReasonCode  = $null
        }

        switch ($Reference.RefKind) {
            'repositoryResource' {
                $result.TargetKind = 'repo'
                $result.Repository = $Reference.Target
                $result.Name = $Reference.Target
                $result.Resolved = $true
            }
            'pipelineResource' {
                $result.TargetKind = 'pipeline'
                $result.Name = $Reference.Target
                $result.Resolved = [bool] $Reference.Target
                if (-not $result.Resolved) {
                    $result.ReasonCode = 'alias-not-declared'
                    $result.Reason = "alias-not-declared: the pipeline resource '$($Reference.Alias)' in $SourcePath names no source definition"
                }
            }
            'checkout' {
                $result.TargetKind = 'repo'
                if ($aliases.ContainsKey($Reference.Alias)) {
                    $result.Repository = $aliases[$Reference.Alias]
                    $result.Name = $result.Repository
                    $result.Resolved = $true
                } else {
                    $result.ReasonCode = 'alias-not-declared'
                    $result.Reason = "alias-not-declared: '$($Reference.Alias)' is not in resources.repositories of $SourcePath, so the repository being checked out is unknown"
                }
            }
            default {
                # template and extends: the two path rules.
                $result.TargetKind = 'yaml'

                if ($Reference.Alias -and -not $aliases.ContainsKey($Reference.Alias)) {
                    # An undeclared alias is not a missing file. It is a missing
                    # resources.repositories entry, and the fixes differ. The
                    # reason keeps the code as a prefix so it stays machine-
                    # readable, and then says WHICH alias, in WHICH file, and
                    # what follows from that -- a bare code makes a reader open
                    # the YAML to learn anything at all.
                    $result.ReasonCode = 'alias-not-declared'
                    $result.Reason = "alias-not-declared: '$($Reference.Alias)' is not in resources.repositories of $SourcePath, so the repository is unknown and the path cannot be resolved at all"
                } else {
                    if ($Reference.Alias) {
                        # From the ROOT of the aliased repository.
                        $result.Repository = $aliases[$Reference.Alias]
                        $result.Path = Resolve-AzDoRelativePath -BaseDirectory '' -Path $Reference.Path
                    } else {
                        # Relative to the DIRECTORY of the file making the reference.
                        $result.Repository = $SourceRepository
                        $directory = if ($SourcePath -match '/') { $SourcePath -replace '/[^/]+$', '' } else { '' }
                        $result.Path = Resolve-AzDoRelativePath -BaseDirectory $directory -Path $Reference.Path
                    }

                    if ($checkExistence) {
                        $key = "$($result.Repository)/$($result.Path)".ToLowerInvariant()
                        if ($canonical.ContainsKey($key)) {
                            $result.Path = ($canonical[$key] -split '/', 2)[1]
                            $result.Resolved = $true
                        } else {
                            # Says where it resolved TO, which is the fact that
                            # distinguishes "the file is missing" from "the rule
                            # sent me to the wrong place".
                            $result.ReasonCode = 'file-not-found'
                            $result.Reason = "file-not-found: resolved to $($result.Path) in $($result.Repository), which does not exist"
                        }
                    } else {
                        $result.Resolved = $true
                    }
                }
            }
        }

        [pscustomobject] $result
    }
}
