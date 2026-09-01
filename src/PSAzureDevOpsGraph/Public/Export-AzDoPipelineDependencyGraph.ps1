function Export-AzDoPipelineDependencyGraph {
    <#
    .SYNOPSIS
        Write a pipeline dependency graph as JSON, DOT or HTML.
    .DESCRIPTION
        JSON is the contract in fixture/graph.schema.json: something to diff and
        something another tool can read. DOT is for Graphviz. HTML is
        self-contained - no external script, stylesheet, font, image or http(s)
        reference of any kind - so it opens from a file:// URL with no network.

        Unresolved references are drawn in every format, visibly distinct from
        resolved ones. A broken pipeline that vanishes from the picture looks
        identical to a clean one.
    .PARAMETER Graph
        A graph from Get-AzDoPipelineDependencyGraph.
    .PARAMETER Format
        Json, Dot or Html. Defaults to Json.
    .PARAMETER Path
        The file to write. Omit it and the rendered text is returned instead, so
        the command composes with a pipeline.
    .PARAMETER PassThru
        Also return the rendered text when Path is given.
    .EXAMPLE
        # Needs $env:AZDO_PAT with Code (Read) and Build (Read).
        Get-AzDoPipelineDependencyGraph -Organisation jlbalmerjr1 -Project ClaudeTesting |
            Export-AzDoPipelineDependencyGraph -Path ./graph.json

        Writes the graph as JSON against the published schema.
    .EXAMPLE
        # Needs $env:AZDO_PAT with Code (Read) and Build (Read).
        $g = Get-AzDoPipelineDependencyGraph -Organisation jlbalmerjr1 -Project ClaudeTesting
        Export-AzDoPipelineDependencyGraph -Graph $g -Format Html -Path ./graph.html

        Writes a page that renders with no network access.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [PSTypeName('PSAzureDevOpsGraph.Graph')] $Graph,

        [ValidateSet('Json', 'Dot', 'Html')] [string] $Format = 'Json',

        [string] $Path,
        [switch] $PassThru
    )

    process {
        $text = switch ($Format) {
            'Json' {
                # PSTypeName is a type-system annotation and is not serialised,
                # so the JSON carries exactly the six contract keys.
                $Graph | ConvertTo-Json -Depth 30
            }
            'Dot' { ConvertTo-AzDoGraphDot -Graph $Graph }
            'Html' { ConvertTo-AzDoGraphHtml -Graph $Graph }
        }

        if (-not $Path) { return $text }

        $directory = Split-Path -Parent $Path
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            $null = New-Item -ItemType Directory -Path $directory -Force
        }
        Set-Content -LiteralPath $Path -Value $text -Encoding utf8NoBOM
        Write-Verbose "Wrote $Format to $Path."

        if ($PassThru) { $text }
    }
}
