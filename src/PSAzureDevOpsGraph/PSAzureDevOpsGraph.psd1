@{
    RootModule           = 'PSAzureDevOpsGraph.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'efae919e-b1c3-4468-a665-5eae847b6259'
    Author               = 'Jerry Balmer'
    CompanyName          = 'Unknown'
    Copyright            = '(c) 2026 Jerry Balmer. All rights reserved.'
    Description          = 'Produces a dependency graph of Azure DevOps pipelines and the repositories and templates they reference. Read-only.'

    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')

    FunctionsToExport    = @(
        'Export-AzDoPipelineDependencyGraph'
        'Get-AzDoPipeline'
        'Get-AzDoPipelineDependencyGraph'
        'Get-AzDoPipelineReference'
        'Get-AzDoPipelineYaml'
        'Get-AzDoRepository'
        'Resolve-AzDoPipelineReference'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('AzureDevOps', 'Pipelines', 'Graph', 'DependencyAnalysis')
            LicenseUri = 'https://github.com/JerryBalmer1/PSAzureDevOpsGraph/blob/main/LICENSE'
            ProjectUri = 'https://github.com/JerryBalmer1/PSAzureDevOpsGraph'
        }
    }
}
