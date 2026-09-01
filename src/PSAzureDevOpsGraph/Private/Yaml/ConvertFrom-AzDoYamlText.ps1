function ConvertFrom-AzDoYamlText {
    <#
    .SYNOPSIS
        Parse YAML text into an object graph, returning $null when it will not parse.
    .DESCRIPTION
        A document that does not parse is data, not a failure. The caller decides
        what an unparseable file means -- for a dependency graph it means the
        file contributes no references, and the rest of the graph still builds.

        powershell-yaml is imported on first use rather than at module load, and
        it is declared in the manifest's RequiredModules so that Import-Module
        cannot succeed on a machine that lacks it.
    .PARAMETER Text
        The YAML document.
    .OUTPUTS
        System.Object
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    if (-not (Get-Module -Name 'powershell-yaml')) {
        Import-Module -Name 'powershell-yaml' -ErrorAction Stop
    }

    try {
        ConvertFrom-Yaml -Yaml $Text -Ordered -ErrorAction Stop
    } catch {
        Write-Verbose "YAML did not parse: $($_.Exception.Message)"
        $null
    }
}
