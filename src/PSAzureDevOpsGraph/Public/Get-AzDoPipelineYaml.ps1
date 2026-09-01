function Get-AzDoPipelineYaml {
    <#
    .SYNOPSIS
        The YAML text of a pipeline definition, or of a path in a repository, at
        a given ref.
    .DESCRIPTION
        Returns a record rather than a bare string so a result traces back to
        the repository, path and ref it came from. The text is on Content.

        A path that does not exist is not an error. Azure DevOps answers 404,
        and for a dependency graph that is a RESULT - an unresolved reference
        with a reason - so this returns nothing and lets the caller say why.
    .PARAMETER Organisation
        The Azure DevOps organisation.
    .PARAMETER Project
        The project. Every route this module calls is project-scoped.
    .PARAMETER Pipeline
        A pipeline record from Get-AzDoPipeline. Its repository and YamlPath say
        what to fetch.
    .PARAMETER Repository
        The repository name holding the file.
    .PARAMETER Path
        The path of the file within that repository.
    .PARAMETER Ref
        The branch or ref to read at. Defaults to the repository's default
        branch when omitted.
    .EXAMPLE
        # Needs $env:AZDO_PAT with Code (Read).
        Get-AzDoPipelineYaml -Organisation jlbalmerjr1 -Project ClaudeTesting -Repository pipelines-main -Path pipelines/p01.yml

        Reads one file and returns its text on the Content property.
    .EXAMPLE
        # Needs $env:AZDO_PAT with Code (Read) and Build (Read).
        Get-AzDoPipeline -Organisation jlbalmerjr1 -Project ClaudeTesting | Get-AzDoPipelineYaml -Organisation jlbalmerjr1 -Project ClaudeTesting

        Reads the YAML behind every definition in the project.
    .OUTPUTS
        PSAzureDevOpsGraph.Yaml
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPath')]
    [OutputType('PSAzureDevOpsGraph.Yaml')]
    param(
        [Parameter(Mandatory, Position = 0)] [ValidateNotNullOrEmpty()] [string] $Organisation,
        [Parameter(Mandatory, Position = 1)] [ValidateNotNullOrEmpty()] [string] $Project,

        [Parameter(Mandatory, ParameterSetName = 'ByPipeline', ValueFromPipeline)]
        [PSTypeName('PSAzureDevOpsGraph.Pipeline')] $Pipeline,

        [Parameter(Mandatory, ParameterSetName = 'ByPath')] [ValidateNotNullOrEmpty()] [string] $Repository,
        [Parameter(Mandatory, ParameterSetName = 'ByPath')] [ValidateNotNullOrEmpty()] [string] $Path,

        [string] $Ref
    )

    process {
        # Target resolution in one step, and nothing else keys off the set.
        $targetRepository = $Repository
        $targetPath = $Path
        if ($PSCmdlet.ParameterSetName -eq 'ByPipeline') {
            if (-not $Pipeline.YamlPath) {
                Write-Verbose "Pipeline '$($Pipeline.Name)' is not a YAML definition; it has no file to read."
                return
            }
            $targetRepository = $Pipeline.Repository
            $targetPath = $Pipeline.YamlPath
        }

        $query = [ordered]@{
            path            = '/' + $targetPath.TrimStart('/')
            includeContent  = 'true'
            '$format'       = 'json'
            'api-version'   = '7.1'
        }
        if ($Ref) { $query['versionDescriptor.version'] = $Ref }

        $uri = "https://dev.azure.com/$Organisation/$Project/_apis/git/repositories/$([uri]::EscapeDataString($targetRepository))/items"
        $item = @(Invoke-AzDoRestMethod -Uri $uri -Query $query)[0]
        if ($null -eq $item) {
            Write-Verbose "No item at '$targetPath' in repository '$targetRepository'."
            return
        }

        [pscustomobject]@{
            PSTypeName = 'PSAzureDevOpsGraph.Yaml'
            Repository = $targetRepository
            Path       = $targetPath.TrimStart('/')
            Ref        = if ($Ref) { $Ref } else { $null }
            Content    = [string] $item.content
        }
    }
}
