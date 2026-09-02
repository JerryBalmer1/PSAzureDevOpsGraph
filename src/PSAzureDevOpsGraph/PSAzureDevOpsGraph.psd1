@{
    RootModule           = 'PSAzureDevOpsGraph.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '7f3c1c2e-9b8a-4e5d-8a1f-2c6d4b9e0a37'
    Author               = 'Jerry Balmer'
    CompanyName          = 'Jerry Balmer'
    Copyright            = '(c) 2026 Jerry Balmer. Released under the MIT licence.'
    Description          = 'Builds a dependency graph of Azure DevOps pipelines and the repositories and templates they reference, so that the blast radius of a template change can be answered. Read-only.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')

    FunctionsToExport    = @(
        'Get-AzDoRepository'
        'Get-AzDoPipeline'
        'Get-AzDoPipelineYaml'
        'Get-AzDoPipelineReference'
        'Resolve-AzDoPipelineReference'
        'Get-AzDoPipelineDependencyGraph'
        'Export-AzDoPipelineDependencyGraph'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('AzureDevOps', 'Pipelines', 'Graph', 'Dependencies', 'ReadOnly')
            LicenseUri   = 'https://github.com/JerryBalmer1/PSAzureDevOpsGraph/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/JerryBalmer1/PSAzureDevOpsGraph'
            ReleaseNotes = 'Initial build: repositories, pipelines, YAML reference parsing, reference resolution, dependency graph, and JSON/DOT/HTML export.'
        }
    }
}
