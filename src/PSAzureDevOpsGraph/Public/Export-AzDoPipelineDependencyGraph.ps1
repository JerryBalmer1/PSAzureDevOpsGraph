function Export-AzDoPipelineDependencyGraph {
    <#
    .SYNOPSIS
        A dependency graph as JSON, DOT or HTML.
    .DESCRIPTION
        JSON is the contract in fixture/graph.schema.json and is what another
        tool reads. DOT is for Graphviz. HTML is self-contained -- no external
        script, stylesheet or http(s):// reference at all -- so it opens from a
        file:// URL with no network.

        Nothing is exported that the graph does not carry. Optional fields the
        graph has nothing to say about stay absent, because in this contract an
        absent field means NOT STATED and writing a value is a louder claim.
    .PARAMETER Graph
        A graph from Get-AzDoPipelineDependencyGraph.
    .PARAMETER Format
        Json (default), Dot or Html.
    .PARAMETER Path
        A file to write. Without it the text is returned.
    .EXAMPLE
        # Needs $env:AZDO_PAT with Code (Read) and Build (Read).
        Get-AzDoPipelineDependencyGraph -Organisation jlbalmerjr1 -Project ClaudeTesting |
            Export-AzDoPipelineDependencyGraph -Format Html -Path ./graph.html

        Writes a self-contained page.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] $Graph,
        [ValidateSet('Json', 'Dot', 'Html')] [string] $Format = 'Json',
        [string] $Path
    )

    process {
        $text = switch ($Format) {
            'Dot' { ConvertTo-AzDoGraphDot -Graph $Graph }
            'Html' { ConvertTo-AzDoGraphHtml -Graph $Graph }
            default {
                # Rebuilt as an ordered map so the JSON carries exactly the
                # schema's six top-level keys and nothing else -- the schema sets
                # additionalProperties false at every level.
                $payload = [ordered]@{
                    version      = $Graph.version
                    organisation = $Graph.organisation
                    project      = $Graph.project
                    generatedBy  = $Graph.generatedBy
                    nodes        = [object[]] @($Graph.nodes)
                    edges        = [object[]] @($Graph.edges)
                }
                $payload | ConvertTo-Json -Depth 10
            }
        }

        if ($Path) {
            $directory = Split-Path -Parent $Path
            if ($directory -and -not (Test-Path -LiteralPath $directory)) {
                $null = New-Item -ItemType Directory -Path $directory -Force
            }
            Set-Content -LiteralPath $Path -Value $text -Encoding utf8NoBOM
            Write-Verbose "Wrote $Format to $Path."
            return
        }

        $text
    }
}
