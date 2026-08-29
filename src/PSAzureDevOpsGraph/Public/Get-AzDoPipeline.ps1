function Get-AzDoPipeline {
    <#
        .SYNOPSIS
            Lists the pipeline definitions in a project, each with the
            repository and path its YAML lives at.

        .DESCRIPTION
            The list route returns definition references only - no repository
            and no yamlFilename - so each definition is fetched by id to learn
            where its YAML is. Read-only throughout; nothing here can queue,
            run, or modify a definition.

        .PARAMETER Organisation
            The Azure DevOps organisation name.

        .PARAMETER Project
            The project name.

        .EXAMPLE
            Get-AzDoPipeline -Organisation contoso -Project ClaudeTesting

            Lists every definition with the repository and path of its YAML.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Organisation,
        [Parameter(Mandatory)] [string] $Project
    )

    $base = 'https://dev.azure.com/{0}/{1}/_apis/build/definitions' -f $Organisation, $Project

    foreach ($reference in (Invoke-AzDoRestMethod -Uri $base -Query @{ 'api-version' = '7.1' })) {
        $definitionUri = '{0}/{1}' -f $base, $reference.id
        $definition = Invoke-AzDoRestMethod -Uri $definitionUri -Query @{ 'api-version' = '7.1' } -Single

        $yamlPath = $null
        if ($definition.PSObject.Properties.Name -contains 'process' -and
            $definition.process.PSObject.Properties.Name -contains 'yamlFilename') {
            $yamlPath = [string] $definition.process.yamlFilename
        }

        [pscustomobject]@{
            Name           = $definition.name
            Id             = $definition.id
            RepositoryName = $definition.repository.name
            RepositoryId   = $definition.repository.id
            Path           = $yamlPath
            Organisation   = $Organisation
            Project        = $Project
        }
    }
}
