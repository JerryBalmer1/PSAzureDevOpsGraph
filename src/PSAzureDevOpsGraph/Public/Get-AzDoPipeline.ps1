function Get-AzDoPipeline {
    <#
    .SYNOPSIS
        The pipeline definitions registered in a project, each with the
        repository and path its YAML lives at.
    .DESCRIPTION
        Read-only. The repository and YAML path are the whole point: a pipeline
        definition is a registration in Azure DevOps pointing at a file in a
        repository, and the graph's first edge is that pointer.

        Uses the build definitions endpoint rather than the pipelines endpoint
        because it returns the repository *name* alongside its id; the pipelines
        endpoint returns the id alone, which would cost one extra request per
        definition to turn back into something a human can read.
    .EXAMPLE
        Get-AzDoPipeline -Organisation jlbalmerjr1 -Project ClaudeTesting
    #>
    [CmdletBinding()]
    [OutputType('PSAzureDevOpsGraph.Pipeline')]
    param(
        [Parameter(Mandatory)][string]$Organisation,
        [Parameter(Mandatory)][string]$Project,
        # Filter by definition name. Wildcards are accepted.
        [string]$Name
    )

    $response = Invoke-AzDoRestMethod -ApiPath 'build/definitions' -Organisation $Organisation -Project $Project -Query @{
        includeAllProperties = 'true'
    }

    foreach ($definition in $response.value) {
        if ($Name -and $definition.name -notlike $Name) { continue }

        $repository = $null
        $repositoryId = $null
        $repositoryType = $null
        if ($definition.PSObject.Properties['repository'] -and $definition.repository) {
            $repository     = $definition.repository.name
            $repositoryId   = $definition.repository.id
            $repositoryType = $definition.repository.type
        }

        $yamlPath = $null
        if ($definition.PSObject.Properties['process'] -and $definition.process) {
            if ($definition.process.PSObject.Properties['yamlFilename']) { $yamlPath = $definition.process.yamlFilename }
        }

        $folder = if ($definition.PSObject.Properties['path']) { $definition.path } else { '\' }

        [pscustomobject]@{
            PSTypeName     = 'PSAzureDevOpsGraph.Pipeline'
            Id             = $definition.id
            Name           = $definition.name
            Folder         = $folder
            Project        = $Project
            Organisation   = $Organisation
            Repository     = $repository
            RepositoryId   = $repositoryId
            RepositoryType = $repositoryType
            # Normalised to repository-relative and forward-slashed: Azure DevOps
            # reports this with a leading slash and the graph does not want one.
            Path           = if ($yamlPath) { ($yamlPath -replace '\\', '/').TrimStart('/') } else { $null }
            IsYaml         = [bool]$yamlPath
            Revision       = $definition.revision
            WebUrl         = if ($definition.PSObject.Properties['_links'] -and $definition._links.PSObject.Properties['web']) { $definition._links.web.href } else { $null }
        }
    }
}
