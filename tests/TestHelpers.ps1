# Dot-sourced by every test file's BeforeAll. Pester 6 discovers and runs per
# file, so nothing leaks between files and there is no shared setup to lean on.

function Import-ModuleUnderTest {
    <#
    .SYNOPSIS
        Imports the BUILT module, which is the artifact users get.
    #>
    [CmdletBinding()]
    param()

    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $built = Join-Path $repositoryRoot 'output/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psd1'
    if (-not (Test-Path -LiteralPath $built)) {
        throw "The built module is not there. Run ./build.ps1 -Task Build first. Looked at: $built"
    }
    Import-Module -Name $built -Force -ErrorAction Stop
    $built
}

function New-AzDoWebResponse {
    <#
    .SYNOPSIS
        The shape Invoke-WebRequest returns, for a mocked Azure DevOps read.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] [object] $Body,
        [string] $ContinuationToken
    )

    $headers = @{ 'Content-Type' = @('application/json; charset=utf-8') }
    if ($ContinuationToken) { $headers['x-ms-continuationtoken'] = @($ContinuationToken) }

    [pscustomobject] @{
        Content = ($Body | ConvertTo-Json -Depth 20)
        Headers = $headers
    }
}
