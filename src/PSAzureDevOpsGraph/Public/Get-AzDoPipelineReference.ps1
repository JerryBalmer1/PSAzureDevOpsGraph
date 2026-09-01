function Get-AzDoPipelineReference {
    <#
    .SYNOPSIS
        The references in one pipeline YAML document.
    .DESCRIPTION
        Parsing only. No network, no credentials, and no knowledge of what
        exists anywhere - which is what makes it testable against a file on
        disk. Where a reference POINTS is Resolve-AzDoPipelineReference's
        question, and keeping the two apart is what makes a failure
        attributable: a combined command reports resolution failures as parsing
        results, with no way to tell which half was wrong.

        Five kinds are recognised: template, extends, repositoryResource,
        pipelineResource and checkout. extends.template is an extends reference,
        not a template one. checkout: self yields nothing at all.

        The document is walked structurally and in full. A reference is a
        mapping key named exactly 'template', so buildTemplate: is not one, and
        a parameter whose value happens to look like a path is not one either.
    .PARAMETER Content
        The YAML text to parse. Accepts the Content property of a
        PSAzureDevOpsGraph.Yaml record from the pipeline.
    .PARAMETER Path
        A YAML file on disk to parse. No credentials are needed for this.
    .EXAMPLE
        Get-AzDoPipelineReference -Content "extends:`n  template: t.yml@shared`n"

        Returns one reference of kind extends, with Alias 'shared' and Path
        't.yml'.
    .EXAMPLE
        Get-AzDoPipelineReference -Path ./tests/fixtures/azure-pipelines.yml

        Parses a file on disk, with no network and no PAT.
    .OUTPUTS
        PSAzureDevOpsGraph.Reference
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByContent')]
    [OutputType('PSAzureDevOpsGraph.Reference')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByContent', Position = 0, ValueFromPipelineByPropertyName)]
        [AllowEmptyString()] [string] $Content,

        [Parameter(Mandatory, ParameterSetName = 'ByPath')]
        [ValidateNotNullOrEmpty()] [string] $Path
    )

    process {
        $text = if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                throw "No file at '$Path'."
            }
            Get-Content -LiteralPath $Path -Raw
        } else {
            $Content
        }

        $document = ConvertFrom-AzDoYamlDocument -Text $text
        if ($null -eq $document) { return }

        Get-AzDoYamlReferenceNode -Node $document
    }
}
