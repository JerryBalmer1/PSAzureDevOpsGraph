function Get-AzDoPipelineReference {
    <#
    .SYNOPSIS
        The references made by one pipeline YAML document.
    .DESCRIPTION
        Parsing only. No network, no credentials, and no knowledge of what
        exists -- which is what makes it testable against a file on disk. Where a
        reference points is Resolve-AzDoPipelineReference's question, and keeping
        the two apart is why a resolution failure can be told from a parse
        failure at all.

        Five kinds are recognised: template, extends, repositoryResource,
        pipelineResource and checkout. The document is walked in full, so a
        template under variables: is found; the key template is matched exactly,
        so buildTemplate: is not; and checkout: self yields nothing.
    .PARAMETER Path
        A YAML file on disk.
    .PARAMETER Yaml
        YAML text.
    .EXAMPLE
        Get-AzDoPipelineReference -Yaml "extends:`n  template: base.yml@shared`n"

        One reference, of kind extends, with Path base.yml and Alias shared.
    .EXAMPLE
        Get-AzDoPipelineReference -Path ./azure-pipelines.yml

        Every reference in a file, with no credential and no network.
    .OUTPUTS
        PSAzureDevOpsGraph.Reference
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPath')]
    [OutputType('PSAzureDevOpsGraph.Reference')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByPath', ValueFromPipeline)]
        [ValidateNotNullOrEmpty()] [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'ByYaml')]
        [AllowEmptyString()] [string] $Yaml
    )

    process {
        $text = if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                throw "No such file: $Path"
            }
            Get-Content -LiteralPath $Path -Raw
        } else {
            $Yaml
        }

        $document = ConvertFrom-AzDoYamlText -Text $text
        if ($null -eq $document) { return }

        Read-AzDoYamlReference -Node $document
    }
}
