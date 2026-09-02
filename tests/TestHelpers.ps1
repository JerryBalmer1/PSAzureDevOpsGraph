# Dot-sourced by every test file's BeforeAll. Discovery and run happen per file
# in Pester 6, so nothing leaks between files and there is no shared setup to
# lean on.

function Import-ModuleUnderTest {
    <#
    .SYNOPSIS
        Import the BUILT module, falling back to the dev loader in src/.
    .DESCRIPTION
        tests/ imports from output/ because that is the artifact users get and
        the only place the generated Export-ModuleMember exists. The fallback
        exists so a unit test can run before anything has been built; it is a
        fallback, not the normal path.
    #>
    [CmdletBinding()]
    param()

    $root = Split-Path -Parent $PSScriptRoot
    $built = Join-Path $root 'output/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psd1'
    $source = Join-Path $root 'src/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psd1'

    $manifest = if (Test-Path -LiteralPath $built) { $built } else { $source }
    Import-Module $manifest -Force -ErrorAction Stop
    Get-Module PSAzureDevOpsGraph
}

function Get-FixtureCoordinate {
    <#
    .SYNOPSIS
        The organisation and project the integration layer reads.
    #>
    [CmdletBinding()]
    param()
    [pscustomobject]@{ Organisation = 'jlbalmerjr1'; Project = 'ClaudeTesting' }
}
