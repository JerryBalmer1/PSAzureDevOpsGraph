#Requires -Version 7.2
BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    Import-BuiltModule

    $script:Graph = [pscustomobject][ordered]@{
        PSTypeName   = 'PSAzureDevOpsGraph.Graph'
        version      = 1
        organisation = 'org'
        project      = 'proj'
        generatedBy  = 'Get-AzDoPipelineDependencyGraph'
        nodes        = @(
            [pscustomobject][ordered]@{ id = 'pipeline:App-CI'; kind = 'pipeline'; name = 'App-CI' }
            [pscustomobject][ordered]@{ id = 'repo:shared'; kind = 'repo'; name = 'shared' }
            [pscustomobject][ordered]@{ id = 'yaml:app/azure-pipelines.yml'; kind = 'yaml'; name = 'azure-pipelines.yml'; repo = 'app'; path = 'repos/app/azure-pipelines.yml' }
        )
        edges        = @(
            [pscustomobject][ordered]@{ from = 'pipeline:App-CI'; to = 'yaml:app/azure-pipelines.yml'; kind = 'definition' }
            [pscustomobject][ordered]@{ from = 'yaml:app/azure-pipelines.yml'; to = 'repo:shared'; kind = 'repositoryResource'; ref = 'shared'; alias = 'sharedTemplates' }
            [pscustomobject][ordered]@{ from = 'yaml:app/azure-pipelines.yml'; to = 'yaml:@nope/ghost/x.yml'; kind = 'unresolved'; ref = 'ghost/x.yml@nope'; refKind = 'template'; reason = 'alias-not-declared' }
        )
    }
    $script:OutputRoot = Join-Path ([IO.Path]::GetTempPath()) "azdograph-$(New-Guid)"
}

AfterAll {
    if (Test-Path -LiteralPath $script:OutputRoot) {
        Remove-Item -LiteralPath $script:OutputRoot -Recurse -Force
    }
}

Describe 'Export-AzDoPipelineDependencyGraph' {

    Context 'JSON is the contract' {

        It 'emits exactly the six contract keys and no type annotation' {
            $json = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Json
            $parsed = $json | ConvertFrom-Json
            @($parsed.PSObject.Properties.Name | Sort-Object) |
                Should-BeCollection @('edges', 'generatedBy', 'nodes', 'organisation', 'project', 'version')
        }

        It 'writes version as a JSON number, not as a string' {
            # Asserted against the TEXT. ConvertFrom-Json widens every integer
            # to [long], so a type assertion on the parsed value would be about
            # the parser rather than about what was written.
            $json = Export-AzDoPipelineDependencyGraph -Graph $script:Graph
            $json | Should-MatchString '"version"\s*:\s*1\s*,'
            ($json | ConvertFrom-Json).version | Should-Be 1
        }

        It 'writes no optional field the source object did not carry' {
            $parsed = (Export-AzDoPipelineDependencyGraph -Graph $script:Graph) | ConvertFrom-Json
            $definition = $parsed.edges | Where-Object kind -eq 'definition'
            $definition.PSObject.Properties.Name | Should-NotContainCollection 'reason'
            $definition.PSObject.Properties.Name | Should-NotContainCollection 'alias'
        }

        It 'writes the file and creates the directory it needs' {
            $path = Join-Path $script:OutputRoot 'nested/graph.json'
            $null = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Path $path
            Test-Path -LiteralPath $path | Should-BeTrue
        }
    }

    Context 'DOT' {

        It 'renders a digraph with a node per graph node' {
            $dot = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Dot
            $dot | Should-MatchString 'digraph PSAzureDevOpsGraph'
            $dot | Should-MatchString '"pipeline:App-CI"'
        }

        It 'gives an unresolved target somewhere to land, drawn differently' {
            $dot = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Dot
            $dot | Should-MatchString 'yaml:@nope/ghost/x\.yml'
            $dot | Should-MatchString 'octagon'
        }
    }

    Context 'HTML is self-contained without qualification' {

        BeforeAll {
            $script:Html = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Html
        }

        It 'renders the graph and the unresolved table' {
            $script:Html | Should-MatchString '<svg'
            $script:Html | Should-MatchString 'alias-not-declared'
        }

        It 'references no external script, stylesheet, image or font' {
            $script:Html | Should-NotMatchString 'https?://'
            $script:Html | Should-NotMatchString '@import'
            $script:Html | Should-NotMatchString '<script'
            $script:Html | Should-NotMatchString '<link\b'
        }

        It 'escapes text that came from YAML nobody in this module authored' {
            $hostile = [pscustomobject][ordered]@{
                PSTypeName   = 'PSAzureDevOpsGraph.Graph'
                version      = 1
                organisation = 'org'
                project      = '<script>alert(1)</script>'
                generatedBy  = 'x'
                nodes        = @([pscustomobject][ordered]@{ id = 'repo:a'; kind = 'repo'; name = '<b>a</b>' })
                edges        = @([pscustomobject][ordered]@{ from = 'repo:a'; to = 'repo:a'; kind = 'checkout'; ref = 'a' })
            }
            $html = Export-AzDoPipelineDependencyGraph -Graph $hostile -Format Html
            $html | Should-NotMatchString '<script>alert'
            $html | Should-MatchString '&lt;b&gt;a&lt;/b&gt;'
        }

        It 'writes the page to disk when asked, and can also return it' {
            $path = Join-Path $script:OutputRoot 'graph.html'
            $text = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Html -Path $path -PassThru
            Test-Path -LiteralPath $path | Should-BeTrue
            $text | Should-MatchString '<svg'
        }
    }

    It 'takes a graph from the pipeline' {
        $json = $script:Graph | Export-AzDoPipelineDependencyGraph
        $json | Should-MatchString 'pipeline:App-CI'
    }
}
