function ConvertFrom-AzDoYamlText {
    <#
        .SYNOPSIS
            Parses pipeline YAML text into an ordered object graph.

        .DESCRIPTION
            Wraps powershell-yaml so the rest of the module never touches the
            parser directly. Returns $null for empty input or unparsable text
            rather than throwing: a pipeline whose YAML does not parse is a
            result the graph should carry, not a crash.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    if (-not (Get-Module -Name 'powershell-yaml')) {
        $available = Get-Module -ListAvailable -Name 'powershell-yaml' |
            Sort-Object Version -Descending | Select-Object -First 1
        if (-not $available) {
            throw "The 'powershell-yaml' module is required to parse pipeline YAML. Install-Module powershell-yaml -Scope CurrentUser"
        }
        Import-Module $available -Force -ErrorAction Stop
    }

    try {
        ConvertFrom-Yaml -Yaml $Text -Ordered
    }
    catch {
        Write-Verbose "YAML did not parse: $($_.Exception.Message)"
        $null
    }
}
