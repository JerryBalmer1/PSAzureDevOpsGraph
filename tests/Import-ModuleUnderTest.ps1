<#
    Imports the module the tests are about.

    Prefers the BUILT module under output/, because that is what ships and what
    coverage is measured against. Falls back to src/ so that the suite can be
    run on its own, before a build, while working on a single function.
#>
$built  = Join-Path $PSScriptRoot '..' 'output' 'PSAzureDevOpsGraph' 'PSAzureDevOpsGraph.psd1'
$source = Join-Path $PSScriptRoot '..' 'src' 'PSAzureDevOpsGraph' 'PSAzureDevOpsGraph.psd1'

$manifest = if (Test-Path -LiteralPath $built) { $built } else { $source }
Import-Module $manifest -Force -ErrorAction Stop
