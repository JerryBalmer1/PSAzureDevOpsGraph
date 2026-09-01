function Get-AzDoPipelineYaml {
    <#
    .SYNOPSIS
        The YAML text of a definition, or of a path in a repository, at a given ref.
    .DESCRIPTION
        A 404 from the item endpoint means the file is not in that repository.
        For a dependency graph that is a RESULT - an unresolved reference with
        reason file-not-found - and not an exception, so this returns $null
        rather than throwing.
    .PARAMETER Organisation
        The Azure DevOps organisation. An input, never discovered.
    .PARAMETER Project
        The project within the organisation.
    .PARAMETER DefinitionId
        A build definition id. Its repository and YAML path are read from the
        definition and the text is fetched from there.
    .PARAMETER Repository
        The repository holding the file, by name or by id.
    .PARAMETER Path
        The path of the file within the repository.
    .PARAMETER Ref
        The branch or tag to read at. Defaults to the repository default branch.
    .EXAMPLE
        Get-AzDoPipelineYaml -Organisation jlbalmerjr1 -Project ClaudeTesting -Repository pipelines-main -Path pipelines/p01.yml

        The text of one file, or $null when the repository holds no such file.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPath')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)] [ValidateNotNullOrEmpty()] [string] $Organisation,
        [Parameter(Mandatory, Position = 1)] [ValidateNotNullOrEmpty()] [string] $Project,
        [Parameter(Mandatory, ParameterSetName = 'ByDefinition')] [int] $DefinitionId,
        [Parameter(Mandatory, ParameterSetName = 'ByPath')] [ValidateNotNullOrEmpty()] [string] $Repository,
        [Parameter(Mandatory, ParameterSetName = 'ByPath')] [ValidateNotNullOrEmpty()] [string] $Path,
        [string] $Ref
    )

    process {
        $repositoryName = $Repository
        $filePath = $Path

        if ($PSCmdlet.ParameterSetName -eq 'ByDefinition') {
            $definition = Get-AzDoPipeline -Organisation $Organisation -Project $Project -Id $DefinitionId
            if (-not $definition) { return $null }
            $repositoryName = $definition.RepositoryName
            $filePath = $definition.YamlPath
        }

        if (-not $repositoryName -or -not $filePath) { return $null }

        $query = @{
            'api-version'    = '7.1'
            'path'           = '/' + ($filePath -replace '^/', '')
            'includeContent' = 'true'
            '$format'        = 'json'
        }
        if ($Ref) {
            $query['versionDescriptor.version'] = $Ref
            $query['versionDescriptor.versionType'] = 'branch'
        }

        $uri = "https://dev.azure.com/$Organisation/$Project/_apis/git/repositories/$([uri]::EscapeDataString($repositoryName))/items"
        $item = @(Invoke-AzDoRestMethod -Uri $uri -Query $query -AllowNotFound) | Select-Object -First 1

        if (-not $item) { return $null }
        if (-not $item.PSObject.Properties['content']) { return $null }
        [string] $item.content
    }
}
