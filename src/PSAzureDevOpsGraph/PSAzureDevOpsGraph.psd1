@{
    RootModule           = 'PSAzureDevOpsGraph.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'e0756610-c227-47b5-ac88-08af0543b2a6'
    Author               = 'Jerry Balmer'
    CompanyName          = 'Unknown'
    Copyright            = '(c) Jerry Balmer. All rights reserved.'
    Description          = 'Produces a dependency graph of Azure DevOps pipelines and the repositories and templates they reference. Read-only.'

    CompatiblePSEditions = @('Core')
    PowerShellVersion    = '7.2'

    # Runtime dependency, and a floor rather than a pin. Build dependencies are
    # pinned in Requirements.psd1 and are a different thing.
    RequiredModules      = @(
        @{ ModuleName = 'powershell-yaml'; ModuleVersion = '0.4.7' }
    )

    # Explicit, all four keys. A key left unset defaults to a wildcard.
    FunctionsToExport    = @(
        'Export-AzDoPipelineDependencyGraph',
        'Get-AzDoPipeline',
        'Get-AzDoPipelineDependencyGraph',
        'Get-AzDoPipelineReference',
        'Get-AzDoPipelineYaml',
        'Get-AzDoRepository',
        'Resolve-AzDoPipelineReference'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('AzureDevOps', 'Pipelines', 'Graph', 'DependencyGraph')
            LicenseUri = ''
            ProjectUri = ''
        }
    }
}
