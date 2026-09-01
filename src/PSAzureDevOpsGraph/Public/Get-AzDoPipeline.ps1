function Get-AzDoPipeline {
    <#
    .SYNOPSIS
        The pipeline definitions registered in a project, each with the repository and path its YAML lives at.
    .DESCRIPTION
        Two calls, on purpose. The list form of build/definitions returns a
        REFERENCE that carries neither process.yamlFilename nor the repository,
        so each definition is fetched by id to learn where its YAML lives. A
        graph built from the list form alone has no definition edges at all.
    .PARAMETER Organisation
        The Azure DevOps organisation. An input, never discovered.
    .PARAMETER Project
        The project within the organisation.
    .PARAMETER Id
        Fetch one definition by id rather than the whole project.
    .EXAMPLE
        Get-AzDoPipeline -Organisation jlbalmerjr1 -Project ClaudeTesting

        Lists every definition in the project, with the repository and path of its YAML.
    .OUTPUTS
        PSAzureDevOpsGraph.Pipeline
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)] [ValidateNotNullOrEmpty()] [string] $Organisation,
        [Parameter(Mandatory, Position = 1)] [ValidateNotNullOrEmpty()] [string] $Project,
        [int[]] $Id
    )

    process {
        $base = "https://dev.azure.com/$Organisation/$Project/_apis/build/definitions"

        $ids = if ($PSBoundParameters.ContainsKey('Id')) {
            $Id
        } else {
            @(Invoke-AzDoRestMethod -Uri $base -Query @{ 'api-version' = '7.1' } | ForEach-Object { $_.id })
        }

        foreach ($definitionId in $ids) {
            $definition = @(Invoke-AzDoRestMethod -Uri "$base/$definitionId" -Query @{ 'api-version' = '7.1' }) |
                Select-Object -First 1
            if (-not $definition) { continue }

            $yamlPath = $null
            if ($definition.PSObject.Properties['process'] -and $definition.process) {
                if ($definition.process.PSObject.Properties['yamlFilename']) {
                    $yamlPath = [string] $definition.process.yamlFilename
                }
            }

            [pscustomobject] @{
                PSTypeName     = 'PSAzureDevOpsGraph.Pipeline'
                Id             = $definition.id
                Name           = $definition.name
                RepositoryId   = if ($definition.PSObject.Properties['repository'] -and $definition.repository) { $definition.repository.id } else { $null }
                RepositoryName = if ($definition.PSObject.Properties['repository'] -and $definition.repository) { $definition.repository.name } else { $null }
                YamlPath       = $yamlPath ? ($yamlPath -replace '^/', '') : $null
                Organisation   = $Organisation
                Project        = $Project
            }
        }
    }
}
