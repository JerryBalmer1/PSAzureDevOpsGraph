function Get-AzDoPipeline {
    <#
    .SYNOPSIS
        The pipeline definitions registered in a project, each with the
        repository and path its YAML lives at.
    .DESCRIPTION
        Two calls, deliberately. The list form of build/definitions returns a
        REFERENCE that carries neither process.yamlFilename nor the repository,
        so each definition is then fetched by id to learn where its YAML lives.
        A single-call implementation returns definitions with no path and the
        graph silently loses every edge below them.

        A classic (non-YAML) definition has no yamlFilename. It is still
        returned, with YamlPath absent, because it is still a pipeline in the
        project and dropping it would make the list disagree with the portal.
    .PARAMETER Organisation
        The Azure DevOps organisation. Not discovered - see Get-AzDoRepository.
    .PARAMETER Project
        The project. Every route this module calls is project-scoped.
    .PARAMETER Name
        Return only the definition with this name.
    .PARAMETER Id
        Return only the definition with this numeric id.
    .EXAMPLE
        # Needs $env:AZDO_PAT with Code (Read) and Build (Read).
        Get-AzDoPipeline -Organisation jlbalmerjr1 -Project ClaudeTesting

        Lists every definition with the repository and path of its YAML.
    .OUTPUTS
        PSAzureDevOpsGraph.Pipeline
    #>
    [CmdletBinding()]
    [OutputType('PSAzureDevOpsGraph.Pipeline')]
    param(
        [Parameter(Mandatory, Position = 0)] [ValidateNotNullOrEmpty()] [string] $Organisation,
        [Parameter(Mandatory, Position = 1)] [ValidateNotNullOrEmpty()] [string] $Project,
        [string] $Name,
        [int]    $Id
    )

    $base = "https://dev.azure.com/$Organisation/$Project/_apis/build/definitions"
    $list = Invoke-AzDoRestMethod -Uri $base -Query @{ 'api-version' = '7.1' }

    foreach ($reference in @($list)) {
        if ($null -eq $reference) { continue }
        if ($Name -and $reference.name -ne $Name) { continue }
        if ($PSBoundParameters.ContainsKey('Id') -and [int] $reference.id -ne $Id) { continue }

        $full = Invoke-AzDoRestMethod -Uri "$base/$([int] $reference.id)" -Query @{ 'api-version' = '7.1' }
        $definition = @($full)[0]
        if ($null -eq $definition) { continue }

        $yamlPath = $null
        if ($definition.PSObject.Properties['process'] -and $definition.process -and
            $definition.process.PSObject.Properties['yamlFilename']) {
            $yamlPath = ([string] $definition.process.yamlFilename).TrimStart('/')
        }

        [pscustomobject]@{
            PSTypeName     = 'PSAzureDevOpsGraph.Pipeline'
            Id             = [int] $definition.id
            Name           = [string] $definition.name
            Project        = $Project
            Repository     = [string] $definition.repository.name
            RepositoryId   = [string] $definition.repository.id
            RepositoryType = [string] $definition.repository.type
            YamlPath       = $yamlPath
            DefaultBranch  = [string] $definition.repository.defaultBranch
            QueueStatus    = [string] $definition.queueStatus
        }
    }
}
