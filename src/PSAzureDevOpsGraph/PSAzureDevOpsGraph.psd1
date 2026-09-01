@{
    RootModule           = 'PSAzureDevOpsGraph.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '474b9cc1-8c36-4eda-8560-fdd056a6fe2b'
    Author               = 'Jerry Balmer'
    CompanyName          = 'Unknown'
    Copyright            = '(c) Jerry Balmer. All rights reserved.'
    Description          = 'Produces a dependency graph of Azure DevOps pipelines and the repositories and templates they reference. Read-only.'

    CompatiblePSEditions = @('Core')
    PowerShellVersion    = '7.2'

    # RUNTIME dependency. The module parses pipeline YAML with powershell-yaml,
    # so a machine that imports it needs the module whether or not it ever runs
    # a build. Build dependencies are a different thing and are pinned in
    # Requirements.psd1; nothing is written in both places.
    RequiredModules      = @(
        @{ ModuleName = 'powershell-yaml'; ModuleVersion = '0.4.7' }
    )

    # Explicit. A key left unset defaults to a wildcard, and VariablesToExport
    # = @() is not the default and must be written.
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
