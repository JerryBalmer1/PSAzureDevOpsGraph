function Export-AzDoPipelineDependencyGraph {
    <#
    .SYNOPSIS
        Writes a dependency graph as JSON, DOT or HTML.
    .DESCRIPTION
        The JSON is the shape in fixture/graph.schema.json. The HTML is
        self-contained - no external script, stylesheet, @import or http(s)
        reference at all - so it renders from a file:// URL with no network.

        Nothing here writes to Azure DevOps. The only thing this command creates
        is a local file.
    .PARAMETER Graph
        The graph, from Get-AzDoPipelineDependencyGraph.
    .PARAMETER Path
        Where to write. Omit it and the rendered text is returned instead.
    .PARAMETER Format
        Json, Dot or Html. Defaults to Json.
    .EXAMPLE
        Get-AzDoPipelineDependencyGraph -Organisation jlbalmerjr1 -Project ClaudeTesting |
            Export-AzDoPipelineDependencyGraph -Path ./graph.json

        Writes the graph as JSON.
    .EXAMPLE
        Export-AzDoPipelineDependencyGraph -Graph $graph -Format Html -Path ./graph.html

        Writes a standalone page that opens with no network.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)] [ValidateNotNull()] [psobject] $Graph,
        [string] $Path,
        [ValidateSet('Json', 'Dot', 'Html')] [string] $Format = 'Json'
    )

    process {
        $text = switch ($Format) {
            'Json' {
                [pscustomobject] @{
                    version      = $Graph.version
                    organisation = $Graph.organisation
                    project      = $Graph.project
                    generatedBy  = $Graph.generatedBy
                    nodes        = @($Graph.nodes)
                    edges        = @($Graph.edges)
                } | ConvertTo-Json -Depth 30
            }
            'Dot' { ConvertTo-AzDoGraphDot -Graph $Graph }
            'Html' { ConvertTo-AzDoGraphHtml -Graph $Graph }
        }

        if ($Path) {
            $directory = Split-Path -Parent $Path
            if ($directory -and -not (Test-Path -LiteralPath $directory)) {
                $null = New-Item -ItemType Directory -Path $directory -Force
            }
            Set-Content -LiteralPath $Path -Value $text -Encoding utf8NoBOM
            return
        }

        $text
    }
}
