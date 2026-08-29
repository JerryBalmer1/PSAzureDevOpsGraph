@{
    RootModule            = 'PSAzureDevOpsGraph.psm1'
    ModuleVersion         = '0.1.0'
    GUID                  = '5071e564-8d86-4b07-bd22-06d201da9bcc'
    Author                = 'Jerry Balmer'
    CompanyName           = 'Jerry Balmer'
    Copyright             = '(c) 2026 Jerry Balmer. MIT.'
    Description           = 'Builds a dependency graph of Azure DevOps pipelines and the repositories and templates they reference. Read-only.'

    PowerShellVersion     = '5.1'
    CompatiblePSEditions  = @('Core', 'Desktop')

    FunctionsToExport     = @(
        'Get-AzDoRepository'
        'Get-AzDoPipeline'
        'Get-AzDoPipelineYaml'
        'Get-AzDoPipelineReference'
        'Resolve-AzDoPipelineReference'
        'Get-AzDoPipelineDependencyGraph'
        'Export-AzDoPipelineDependencyGraph'
    )
    CmdletsToExport       = @()
    VariablesToExport     = @()
    AliasesToExport       = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('AzureDevOps', 'Pipelines', 'Graph', 'DevOps', 'ReadOnly')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/JerryBalmer1/PSAzureDevOpsGraph'
            ReleaseNotes = 'Initial release. Read-only pipeline dependency graph.'
        }
    }
}
