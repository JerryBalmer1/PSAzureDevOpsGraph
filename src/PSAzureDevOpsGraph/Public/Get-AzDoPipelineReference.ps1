function Get-AzDoPipelineReference {
    <#
    .SYNOPSIS
        The references in one pipeline YAML document.
    .DESCRIPTION
        Parsing only - no resolution, no network, no credentials. That is the
        whole reason this is separate from Resolve-AzDoPipelineReference: a
        combined command reports resolution failures as parsing results, with no
        way to tell which half was wrong.

        The document is walked structurally rather than scanned as text.
        buildTemplate is not template, and a parameter whose value happens to be
        a real path is not a reference - parameter defaults are chosen to be real
        paths precisely so that a text scan produces an edge that resolves and
        therefore looks correct.

        repositoryResource records carry the alias they declare, so the aliases a
        file declares arrive alongside the references that use them.
    .PARAMETER Yaml
        The YAML text of one document.
    .PARAMETER Path
        A file on disk holding one document.
    .EXAMPLE
        Get-AzDoPipelineReference -Yaml (Get-Content ./azure-pipelines.yml -Raw)

        Every template, extends, resource and checkout reference in the document.
    .OUTPUTS
        PSAzureDevOpsGraph.Reference
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByYaml')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByYaml', ValueFromPipeline)]
        [AllowEmptyString()] [string] $Yaml,

        [Parameter(Mandatory, ParameterSetName = 'ByPath')]
        [ValidateNotNullOrEmpty()] [string] $Path
    )

    process {
        $text = if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
            Get-Content -LiteralPath $Path -Raw
        } else {
            $Yaml
        }

        if ([string]::IsNullOrWhiteSpace($text)) { return }

        $document = $null
        try {
            $document = ConvertFrom-Yaml -Yaml $text -Ordered -ErrorAction Stop
        } catch {
            Write-Verbose "The document did not parse as YAML: $($_.Exception.Message)"
            return
        }

        Find-AzDoYamlReference -Node $document
    }
}
