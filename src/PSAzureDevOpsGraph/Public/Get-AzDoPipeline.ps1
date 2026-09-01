function Get-AzDoPipeline {
    <#
    .SYNOPSIS
        The pipeline definitions registered in a project, each with the
        repository and path its YAML lives at.
    .DESCRIPTION
        Two calls, deliberately. The list form of build/definitions returns a
        REFERENCE that carries neither process.yamlFilename nor the repository,
        so every definition is fetched by id to learn where its YAML actually
        lives. Skipping the second call yields a definition list that looks
        complete and cannot be joined to any file.

        A definition whose process is not YAML (a classic designer build) has no
        YAML path; it is still a definition and is still returned, with
        YamlPath $null.
    .PARAMETER Organisation
        The Azure DevOps organisation. An input, never discovered.
    .PARAMETER Project
        The project name.
    .PARAMETER Name
        Return only the definition with this name.
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
        [string] $Name
    )

    process {
        $base = "https://dev.azure.com/$Organisation/$Project/_apis/build/definitions"
        $references = Invoke-AzDoRestMethod -Uri $base -Query @{ 'api-version' = '7.1' }

        foreach ($reference in $references) {
            if ($Name -and $reference.name -ne $Name) { continue }

            $definition = @(Invoke-AzDoRestMethod -Uri "$base/$($reference.id)" -Query @{ 'api-version' = '7.1' })[0]
            if ($null -eq $definition) { continue }

            $yamlPath = $null
            if ($definition.PSObject.Properties['process'] -and $definition.process) {
                if ($definition.process.PSObject.Properties['yamlFilename']) {
                    $yamlPath = [string] $definition.process.yamlFilename
                }
            }

            [pscustomobject]@{
                PSTypeName     = 'PSAzureDevOpsGraph.Pipeline'
                Name           = $definition.name
                Id             = $definition.id
                RepositoryName = $definition.repository.name
                RepositoryId   = $definition.repository.id
                YamlPath       = if ($yamlPath) { $yamlPath.TrimStart('/') } else { $null }
                DefaultBranch  = $definition.repository.defaultBranch
                Organisation   = $Organisation
                Project        = $Project
            }
        }
    }
}
