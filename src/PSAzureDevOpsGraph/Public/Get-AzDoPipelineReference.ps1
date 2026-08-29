function Get-AzDoPipelineReference {
    <#
        .SYNOPSIS
            Returns the references in one pipeline YAML document.

        .DESCRIPTION
            Parsing only - no resolution, no network, no credentials. That
            separation is deliberate: parsing is testable against a file on
            disk, while resolution needs to know what exists in which
            repository. A combined command reports resolution failures as
            parsing results, with no way to tell which half was wrong.

            Finds template, extends, resources.repositories,
            resources.pipelines and checkout. A key named exactly 'template'
            is a reference; 'buildTemplate' is not, and neither is a parameter
            whose value happens to be a real template path.

        .PARAMETER Yaml
            The YAML text to parse.

        .PARAMETER Path
            Optional. The repository-relative path the text came from, echoed
            onto each reference so a caller can resolve it later.

        .EXAMPLE
            Get-AzDoPipelineReference -Yaml (Get-Content ./p04.yml -Raw)

            Lists the two cross-repository template references and the two
            repository resources that make their aliases resolvable.

        .EXAMPLE
            $refs = Get-AzDoPipelineReference -Yaml $text
            $refs | Where-Object RefKind -eq 'repositoryResource'

            The alias declarations, which Resolve-AzDoPipelineReference needs.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Yaml,

        [string] $Path
    )

    process {
        $document = ConvertFrom-AzDoYamlText -Text $Yaml
        foreach ($reference in (Find-AzDoYamlReference -Document $document)) {
            [pscustomobject]@{
                RefKind    = $reference.RefKind
                Ref        = $reference.Ref
                Path       = $reference.Path
                Alias      = $reference.Alias
                Target     = $reference.Target
                SourcePath = $Path
            }
        }
    }
}
