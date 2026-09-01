function Get-AzDoPipelineYaml {
    <#
    .SYNOPSIS
        The YAML text of a pipeline definition, or of a path in a repository, at
        a given ref.
    .DESCRIPTION
        Two parameter sets, because there are two ways to name the document and
        only one of them is a file: ByDefinition resolves the definition to its
        repository and path first, ByPath goes straight to the file.

        A path that is not in the repository returns $null rather than throwing.
        For a dependency graph that absence is the answer, not a failure.
    .PARAMETER Organisation
        The Azure DevOps organisation. An input, never discovered.
    .PARAMETER Project
        The project name.
    .PARAMETER PipelineId
        A build definition id. Its repository and YAML path are looked up.
    .PARAMETER RepositoryName
        The repository holding the file.
    .PARAMETER Path
        The path within the repository.
    .PARAMETER Ref
        A branch name. Defaults to the repository default branch.
    .EXAMPLE
        # Needs $env:AZDO_PAT with Code (Read) and Build (Read).
        Get-AzDoPipelineYaml -Organisation jlbalmerjr1 -Project ClaudeTesting -RepositoryName pipelines-main -Path pipelines/p01.yml

        The text of one file.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPath')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)] [ValidateNotNullOrEmpty()] [string] $Organisation,
        [Parameter(Mandatory, Position = 1)] [ValidateNotNullOrEmpty()] [string] $Project,

        [Parameter(Mandatory, ParameterSetName = 'ByDefinition')] [int] $PipelineId,

        [Parameter(Mandatory, ParameterSetName = 'ByPath')] [ValidateNotNullOrEmpty()] [string] $RepositoryName,
        [Parameter(Mandatory, ParameterSetName = 'ByPath')] [ValidateNotNullOrEmpty()] [string] $Path,

        [string] $Ref
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByDefinition') {
            $definition = @(Invoke-AzDoRestMethod -Uri "https://dev.azure.com/$Organisation/$Project/_apis/build/definitions/$PipelineId" -Query @{ 'api-version' = '7.1' })[0]
            if ($null -eq $definition) { return $null }

            $yamlPath = $null
            if ($definition.PSObject.Properties['process'] -and $definition.process -and $definition.process.PSObject.Properties['yamlFilename']) {
                $yamlPath = [string] $definition.process.yamlFilename
            }
            if (-not $yamlPath) {
                Write-Verbose "Definition $PipelineId has no YAML process."
                return $null
            }

            return Get-AzDoItemContent -Organisation $Organisation -Project $Project -RepositoryId $definition.repository.id -Path $yamlPath -Ref $Ref
        }

        $repository = Get-AzDoRepository -Organisation $Organisation -Project $Project -Name $RepositoryName | Select-Object -First 1
        if ($null -eq $repository) {
            Write-Verbose "No repository named '$RepositoryName' in $Project."
            return $null
        }

        Get-AzDoItemContent -Organisation $Organisation -Project $Project -RepositoryId $repository.Id -Path $Path -Ref $Ref
    }
}
