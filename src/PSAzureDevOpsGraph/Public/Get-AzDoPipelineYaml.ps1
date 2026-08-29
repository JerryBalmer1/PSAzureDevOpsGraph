Set-StrictMode -Version 3.0

function Get-AzDoPipelineYaml {
    <#
    .SYNOPSIS
        The YAML text of a pipeline definition, or of a path in a repository.

    .DESCRIPTION
        Read-only. Two ways in:

        -PipelineId   the definition's own YAML, found via its configuration.
        -Repository   any path in a repository, at a given ref.

        The second form is what walking a template chain needs: a referenced
        template is a path in a repository, not a definition, and has no
        pipeline id of its own.

        A path that does not exist returns nothing rather than throwing, so a
        caller resolving a broken reference can tell "absent" from "failed"
        without parsing an error message.

    .PARAMETER Organisation
        The Azure DevOps organisation name.

    .PARAMETER Project
        The project name.

    .PARAMETER PipelineId
        Id of a pipeline definition; its configured YAML is returned.

    .PARAMETER Repository
        Name or id of the repository to read the path from.

    .PARAMETER Path
        Path within the repository.

    .PARAMETER Ref
        Branch or tag. Defaults to the repository's default branch.

    .EXAMPLE
        Get-AzDoPipelineYaml -Organisation contoso -Project Platform -PipelineId 12

    .EXAMPLE
        Get-AzDoPipelineYaml -Organisation contoso -Project Platform `
                             -Repository templates-shared -Path steps/common.yml
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPipeline')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Organisation,
        [Parameter(Mandatory)][string] $Project,

        [Parameter(Mandatory, ParameterSetName = 'ByPipeline')]
        [int] $PipelineId,

        [Parameter(Mandatory, ParameterSetName = 'ByPath')]
        [string] $Repository,

        [Parameter(Mandatory, ParameterSetName = 'ByPath')]
        [string] $Path,

        [Parameter()][string] $Ref
    )

    if ($PSCmdlet.ParameterSetName -eq 'ByPipeline') {
        $pipeline = Get-AzDoPipeline -Organisation $Organisation -Project $Project -Id $PipelineId

        if (-not $pipeline) { throw "No pipeline definition with id $PipelineId in project '$Project'." }
        if (-not $pipeline.YamlPath) {
            throw "Pipeline '$($pipeline.Name)' (id $PipelineId) has no YAML configuration; its type is '$($pipeline.ConfigurationType)'."
        }

        $Repository = $pipeline.RepositoryName
        $Path       = $pipeline.YamlPath
    }

    $repoId = $Repository
    if ($Repository -notmatch '^[0-9a-fA-F-]{36}$') {
        $match = Get-AzDoRepository -Organisation $Organisation -Project $Project -Name $Repository
        if (-not $match) { return }
        $repoId = $match.Id
    }

    $query = @{
        path             = '/' + (ConvertTo-AzDoRepositoryRelativePath -Path $Path)
        includeContent   = 'true'
        '$format'        = 'json'
    }
    if ($Ref) {
        $query['versionDescriptor.version']     = ($Ref -replace '^refs/heads/', '')
        $query['versionDescriptor.versionType'] = 'branch'
    }

    try {
        $item = Invoke-AzDoRestMethod -Organisation $Organisation -Project $Project `
                                      -Resource ('git/repositories/{0}/items' -f $repoId) -Query $query
    }
    catch {
        if (Test-AzDoNotFound -ErrorRecord $_) { return }
        throw
    }

    if ($null -eq $item) { return }
    if ($item.PSObject.Properties.Name -contains 'content') { return [string]$item.content }

    return
}
