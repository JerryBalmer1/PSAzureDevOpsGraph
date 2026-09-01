# DEV LOADER. Not the build product.
#
# The build concatenates Private/** then Public/* into
# output/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psm1 and that generated file is
# what ships. This exists so the manifest in src/ is importable directly --
# RootModule names a psm1 beside the manifest, and without this file
# Import-Module ./src/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psd1 fails outright.
#
# It DOT-SOURCES rather than concatenating, so $script:ModuleRoot means the same
# thing under both loaders and any asset resolves either way.
$script:ModuleRoot = $PSScriptRoot

foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Private') -Filter *.ps1 -Recurse -File | Sort-Object FullName) +
    @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Public') -Filter *.ps1 -File | Sort-Object Name)) {
    . $file.FullName
}

# The same set as the manifest's FunctionsToExport. This is the fourth corner of
# the export list and the conformance suite does not grade it -- keep it in step
# by hand, or a test passes against a function that is not shipped.
Export-ModuleMember -Function 'Export-AzDoPipelineDependencyGraph',
'Get-AzDoPipeline',
'Get-AzDoPipelineDependencyGraph',
'Get-AzDoPipelineReference',
'Get-AzDoPipelineYaml',
'Get-AzDoRepository',
'Resolve-AzDoPipelineReference'
