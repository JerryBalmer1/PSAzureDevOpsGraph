# Dot-sourced by every test file's BeforeAll. Pester 6 runs discovery and
# execution per file, so nothing leaks between files and there is no shared
# setup to lean on.

$script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
$script:ModuleName = 'PSAzureDevOpsGraph'

function Get-BuiltModuleManifest {
    Join-Path $script:RepositoryRoot "output/$script:ModuleName/$script:ModuleName.psd1"
}

function Import-BuiltModule {
    # The BUILT artifact, not src/. That is what users get, and the only place
    # the generated Export-ModuleMember exists.
    $manifest = Get-BuiltModuleManifest
    if (-not (Test-Path -LiteralPath $manifest)) {
        throw "No built module at '$manifest'. Run ./build.ps1 -Task Build first."
    }
    Import-Module -Name $manifest -Force -ErrorAction Stop
    Get-Module $script:ModuleName
}

function Get-YamlFixturePath {
    param([Parameter(Mandatory)] [string] $Name)
    Join-Path $PSScriptRoot "fixtures/yaml/$Name"
}

function New-RestResponse {
    <#
        A stand-in for what Invoke-WebRequest returns: Content as JSON text and
        a Headers dictionary, because Azure DevOps pages with a continuation
        token in a header rather than in the body.
    #>
    param(
        [Parameter(Mandatory)] $Body,
        [hashtable] $Headers = @{},
        [int] $StatusCode = 200
    )
    $all = @{ 'Content-Type' = 'application/json; charset=utf-8' } + $Headers
    [pscustomobject]@{
        StatusCode = $StatusCode
        Content    = ($Body | ConvertTo-Json -Depth 20)
        Headers    = $all
    }
}
