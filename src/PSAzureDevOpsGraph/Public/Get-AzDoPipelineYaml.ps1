function Get-AzDoPipelineYaml {
    <#
    .SYNOPSIS
        The YAML text of a pipeline definition, or of a path in a repository, at
        a given ref.
    .DESCRIPTION
        Read-only. Returns the text together with the repository and path it came
        from, so that the result can be piped straight into
        Get-AzDoPipelineReference without restating its provenance.

        A missing file is not an error. Half of what this module exists to report
        is references that point at files which are not there, and a terminating
        error on the first missing template would stop the walk at exactly the
        interesting case. Absence is reported as Found = $false.
    .EXAMPLE
        Get-AzDoPipelineYaml -Organisation jlbalmerjr1 -Project ClaudeTesting -Repository shared -Path templates/build.yml
    .EXAMPLE
        Get-AzDoPipeline -Organisation o -Project p | Get-AzDoPipelineYaml
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('PSAzureDevOpsGraph.PipelineYaml')]
    param(
        [Parameter(Mandatory)][string]$Organisation,
        [Parameter(Mandatory)][string]$Project,

        [Parameter(Mandatory, ParameterSetName = 'Path', ValueFromPipelineByPropertyName)]
        [string]$Repository,

        [Parameter(Mandatory, ParameterSetName = 'Path', ValueFromPipelineByPropertyName)]
        [string]$Path,

        # A pipeline definition id, or an object from Get-AzDoPipeline.
        [Parameter(Mandatory, ParameterSetName = 'Definition', ValueFromPipeline)]
        [object]$Definition,

        # Branch name. Defaults to the repository's default branch.
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Ref
    )

    begin {
        $repositoryCache = @{}
        $resolveRepository = {
            param([string]$RepositoryName)
            if (-not $repositoryCache.ContainsKey($RepositoryName)) {
                $match = Get-AzDoRepository -Organisation $Organisation -Project $Project |
                    Where-Object { $_.Name -eq $RepositoryName } | Select-Object -First 1
                $repositoryCache[$RepositoryName] = $match
            }
            $repositoryCache[$RepositoryName]
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Definition') {
            if ($Definition -is [string] -or $Definition -is [int]) {
                $Definition = Get-AzDoPipeline -Organisation $Organisation -Project $Project |
                    Where-Object { $_.Id -eq $Definition -or $_.Name -eq $Definition } | Select-Object -First 1
                if (-not $Definition) { throw "No pipeline definition matched." }
            }
            $Repository = $Definition.Repository
            $Path       = $Definition.Path
            if (-not $Path) {
                Write-Verbose "Definition '$($Definition.Name)' is not a YAML pipeline; nothing to fetch."
                return
            }
        }

        $repo = & $resolveRepository $Repository
        if (-not $repo) {
            [pscustomobject]@{
                PSTypeName       = 'PSAzureDevOpsGraph.PipelineYaml'
                Repository       = $Repository
                Path             = $Path
                Ref              = $Ref
                Found            = $false
                Reason           = "repository '$Repository' not found in project '$Project'"
                Yaml             = $null
                SourceRepository = $Repository
                SourcePath       = $Path
            }
            return
        }

        $normalised = ($Path -replace '\\', '/').TrimStart('/')
        $query = @{
            path                            = '/' + $normalised
            includeContent                  = 'true'
            'versionDescriptor.versionType' = 'branch'
        }
        $branch = $Ref
        if (-not $branch -and $repo.DefaultBranch) { $branch = ($repo.DefaultBranch -replace '^refs/heads/', '') }
        if ($branch) { $query['versionDescriptor.version'] = ($branch -replace '^refs/heads/', '') }
        else { $query.Remove('versionDescriptor.versionType') }

        $found  = $true
        $reason = $null
        $text   = $null
        try {
            $item = Invoke-AzDoRestMethod -ApiPath "git/repositories/$($repo.Id)/items" -Organisation $Organisation -Project $Project -Query $query
            if ($item -and $item.PSObject.Properties['content']) { $text = $item.content }
            elseif ($item -is [string]) { $text = $item }
            else { $found = $false; $reason = "file '$normalised' not found in repository '$Repository'" }
        }
        catch {
            $found  = $false
            $reason = "file '$normalised' not found in repository '$Repository'"
            Write-Verbose "Fetch failed for $Repository/$normalised : $($_.Exception.Message)"
        }

        [pscustomobject]@{
            PSTypeName       = 'PSAzureDevOpsGraph.PipelineYaml'
            Repository       = $repo.Name
            Path             = $normalised
            Ref              = $branch
            Found            = $found
            Reason           = $reason
            Yaml             = $text
            SourceRepository = $repo.Name
            SourcePath       = $normalised
        }
    }
}
