@{
    RootModule           = 'PSAzureDevOpsGraph.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'e568baae-f25d-4c10-8e8f-33f0759e7e8c'
    Author               = 'Jerry Balmer'
    CompanyName          = 'Unknown'
    Copyright            = '(c) Jerry Balmer. All rights reserved.'
    Description          = 'Produces a dependency graph of Azure DevOps pipelines and the repositories and templates they reference. Read-only.'

    CompatiblePSEditions = @('Core')
    PowerShellVersion    = '7.2'

    # RUNTIME dependency. Build dependencies are pinned in Requirements.psd1 and
    # nowhere else; these two lists are different things. Without this entry,
    # Import-Module succeeds on a machine with no YAML parser and the module
    # fails only when a document is parsed.
    RequiredModules      = @(
        @{ ModuleName = 'powershell-yaml'; ModuleVersion = '0.4.7' }
    )

    # Explicit names. A key left unset defaults to a wildcard, and
    # VariablesToExport = @() is not the default and must be written.
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
            LicenseUri = 'https://github.com/JerryBalmer1/PSAzureDevOpsGraph/blob/main/LICENSE'
            ProjectUri = 'https://github.com/JerryBalmer1/PSAzureDevOpsGraph'
        }
    }
}
