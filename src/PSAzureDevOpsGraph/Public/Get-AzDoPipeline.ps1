Set-StrictMode -Version 3.0

function Get-AzDoPipeline {
    <#
    .SYNOPSIS
        The pipeline definitions registered in an Azure DevOps project.

    .DESCRIPTION
        Read-only. Lists definitions and, for each, the repository and path its
        YAML lives at -- which is the join the dependency graph is built on.

        The list route does not carry the configuration, so each definition is
        fetched individually. Classic (non-YAML) definitions are returned with
        YamlPath = $null and ConfigurationType reporting what they are; they
        have no YAML to walk, and silently omitting them would misrepresent the
        project as smaller than it is.

    .PARAMETER Organisation
        The Azure DevOps organisation name.

    .PARAMETER Project
        The project name.

    .PARAMETER Name
        Return only the definition with this name.

    .PARAMETER Id
        Return only the definition with this id.

    .EXAMPLE
        Get-AzDoPipeline -Organisation contoso -Project Platform
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Organisation,
        [Parameter(Mandatory)][string] $Project,
        [Parameter()][string] $Name,
        [Parameter()][int] $Id
    )

    $repositoryName = @{}
    foreach ($repo in Get-AzDoRepository -Organisation $Organisation -Project $Project) {
        $repositoryName[[string]$repo.Id] = $repo.Name
    }

    $list = Invoke-AzDoRestMethod -Organisation $Organisation -Project $Project -Resource 'pipelines'

    foreach ($summary in $list.value) {
        if ($Name -and $summary.name -ne $Name) { continue }
        if ($PSBoundParameters.ContainsKey('Id') -and [int]$summary.id -ne $Id) { continue }

        $detail = Invoke-AzDoRestMethod -Organisation $Organisation -Project $Project -Resource ('pipelines/{0}' -f $summary.id)

        $configType = $null
        $yamlPath   = $null
        $repoId     = $null

        if ($detail.PSObject.Properties.Name -contains 'configuration' -and $detail.configuration) {
            $config = $detail.configuration

            if ($config.PSObject.Properties.Name -contains 'type')  { $configType = $config.type }
            if ($config.PSObject.Properties.Name -contains 'path')  { $yamlPath = ConvertTo-AzDoRepositoryRelativePath -Path ([string]$config.path) }

            if ($config.PSObject.Properties.Name -contains 'repository' -and $config.repository -and
                $config.repository.PSObject.Properties.Name -contains 'id') {
                $repoId = [string]$config.repository.id
            }
        }

        [pscustomobject]@{
            PSTypeName        = 'PSAzureDevOpsGraph.Pipeline'
            Id                = $summary.id
            Name              = $summary.name
            Folder            = if ($summary.PSObject.Properties.Name -contains 'folder') { $summary.folder } else { $null }
            Project           = $Project
            Organisation      = $Organisation
            ConfigurationType = $configType
            YamlPath          = $yamlPath
            RepositoryId      = $repoId
            RepositoryName    = if ($repoId -and $repositoryName.ContainsKey($repoId)) { $repositoryName[$repoId] } else { $null }
        }
    }
}
