Set-StrictMode -Version 3.0

# Dot-source Private first: Public functions depend on them at definition time
# only through calls, but keeping the order fixed makes load failures legible.
foreach ($scope in 'Private', 'Public') {
    $dir = Join-Path -Path $PSScriptRoot -ChildPath $scope
    if (-not (Test-Path -LiteralPath $dir)) { continue }

    foreach ($file in Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File | Sort-Object Name) {
        try {
            . $file.FullName
        }
        catch {
            throw "Failed to load $($file.FullName): $($_.Exception.Message)"
        }
    }
}

$public = @(
    'Get-AzDoRepository'
    'Get-AzDoPipeline'
    'Get-AzDoPipelineYaml'
    'Get-AzDoPipelineReference'
    'Resolve-AzDoPipelineReference'
    'Get-AzDoPipelineDependencyGraph'
    'Export-AzDoPipelineDependencyGraph'
)

Export-ModuleMember -Function $public
