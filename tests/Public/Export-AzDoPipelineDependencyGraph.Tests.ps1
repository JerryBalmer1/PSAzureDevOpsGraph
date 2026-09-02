#Requires -Version 7.2

BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    $script:Module = Import-ModuleUnderTest

    $script:Graph = [pscustomobject]@{
        version      = 1
        organisation = 'contoso'
        project      = 'platform'
        generatedBy  = 'Get-AzDoPipelineDependencyGraph'
        nodes        = @(
            [pscustomobject][ordered]@{ id = 'pipeline:p01'; kind = 'pipeline'; name = 'p01' }
            [pscustomobject][ordered]@{ id = 'repo:shared'; kind = 'repo'; name = 'shared' }
            [pscustomobject][ordered]@{ id = 'yaml:main/pipelines/p01.yml'; kind = 'yaml'; name = 'pipelines/p01.yml'; repo = 'main'; path = 'repos/main/pipelines/p01.yml' }
        )
        edges        = @(
            [pscustomobject][ordered]@{ from = 'pipeline:p01'; to = 'yaml:main/pipelines/p01.yml'; kind = 'definition' }
            [pscustomobject][ordered]@{ from = 'yaml:main/pipelines/p01.yml'; to = 'yaml:@ghost/steps/common.yml'; kind = 'unresolved'; ref = 'steps/common.yml@ghost'; refKind = 'template'; alias = 'ghost'; reason = 'alias-not-declared' }
        )
    }
}

Describe 'Export-AzDoPipelineDependencyGraph' {

    It 'writes JSON carrying exactly the schema top-level keys' {
        $json = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Json
        $back = $json | ConvertFrom-Json
        $names = @($back.PSObject.Properties.Name | Sort-Object)
        $names | Should-BeCollection @('edges', 'generatedBy', 'nodes', 'organisation', 'project', 'version')
    }

    It 'keeps nodes and edges as arrays' {
        $back = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Json | ConvertFrom-Json
        @($back.nodes).Count | Should-Be 3
        @($back.edges).Count | Should-Be 2
    }

    It 'writes no optional field the graph did not carry' {
        # Absent means NOT STATED in this contract. Writing a value is a
        # different claim, and a louder one.
        $back = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Json | ConvertFrom-Json
        $definition = $back.edges | Where-Object kind -eq 'definition'
        $definition.PSObject.Properties.Name | Should-NotContainCollection 'ref'
        $pipelineNode = $back.nodes | Where-Object id -eq 'pipeline:p01'
        $pipelineNode.PSObject.Properties.Name | Should-NotContainCollection 'path'
    }

    It 'writes DOT naming every node and drawing unresolved targets distinctly' {
        $dot = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Dot
        $dot | Should-MatchString 'digraph'
        $dot | Should-MatchString 'yaml:@ghost/steps/common.yml'
        $dot | Should-MatchString 'style=dashed'
    }

    It 'writes HTML that is genuinely self-contained' {
        # No external script, stylesheet, @import, font, image or http(s)
        # reference at all, so it renders from a file:// URL with no network.
        $html = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Html
        $html | Should-NotMatchString 'https?://'
        $html | Should-NotMatchString '@import'
        $html | Should-NotMatchString '<script'
        $html | Should-NotMatchString '<link'
        $html | Should-MatchString 'alias-not-declared'
    }

    It 'writes to a path and creates the directory' {
        $target = Join-Path $TestDrive 'nested/deeper/graph.json'
        Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Json -Path $target
        Test-Path -LiteralPath $target | Should-BeTrue
    }

    It 'accepts the graph from the pipeline' {
        $html = $script:Graph | Export-AzDoPipelineDependencyGraph -Format Html
        $html | Should-MatchString 'Pipeline dependency graph'
    }

    It 'defaults to JSON' {
        $text = Export-AzDoPipelineDependencyGraph -Graph $script:Graph
        $text | Should-MatchString '"version"'
    }
}
