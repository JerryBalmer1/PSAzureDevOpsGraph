BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    Import-ModuleUnderTest | Out-Null

    $script:Graph = [pscustomobject] @{
        version      = 1
        organisation = 'org'
        project      = 'proj'
        generatedBy  = 'Get-AzDoPipelineDependencyGraph'
        nodes        = @(
            [pscustomobject] ([ordered] @{ id = 'pipeline:P01'; kind = 'pipeline'; name = 'P01' })
            [pscustomobject] ([ordered] @{ id = 'repo:shared'; kind = 'repo'; name = 'shared' })
            [pscustomobject] ([ordered] @{ id = 'yaml:main/p01.yml'; kind = 'yaml'; name = 'p01.yml'; repo = 'main'; path = 'repos/main/p01.yml' })
        )
        edges        = @(
            [pscustomobject] ([ordered] @{ from = 'pipeline:P01'; to = 'yaml:main/p01.yml'; kind = 'definition' })
            [pscustomobject] ([ordered] @{ from = 'yaml:main/p01.yml'; to = 'repo:shared'; kind = 'checkout'; ref = 'shared'; alias = 'shared' })
            [pscustomobject] ([ordered] @{ from = 'yaml:main/p01.yml'; to = 'yaml:@ghost/x.yml'; kind = 'unresolved'; ref = 'x.yml@ghost'; refKind = 'template'; alias = 'ghost'; reason = 'alias-not-declared' })
        )
    }
}

Describe 'Export-AzDoPipelineDependencyGraph' {

    It 'writes JSON carrying the whole graph' {
        $json = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Json | ConvertFrom-Json
        $json.version | Should-Be 1
        $json.organisation | Should-Be 'org'
        @($json.nodes).Count | Should-Be 3
        @($json.edges).Count | Should-Be 3
    }

    It 'omits an optional field it has nothing to say about, rather than writing a null' {
        # An absent optional field means NOT STATED. A definition edge is a claim
        # about the project rather than about a file, so it carries no ref.
        $json = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Json | ConvertFrom-Json
        $definition = $json.edges | Where-Object { $_.kind -eq 'definition' }
        $definition.PSObject.Properties.Name | Should-NotContainCollection -Expected 'ref'
        $definition.PSObject.Properties.Name | Should-NotContainCollection -Expected 'reason'
    }

    It 'writes DOT with the unresolved target drawn distinctly' {
        $dot = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Dot
        $dot | Should-MatchString 'digraph PipelineDependencies'
        $dot | Should-MatchString 'yaml:@ghost/x\.yml'
        $dot | Should-MatchString 'style=dashed'
    }

    It 'writes HTML that is self-contained' {
        $html = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Html
        $html | Should-MatchString '<!DOCTYPE html>'
        # No external script, stylesheet, @import or http(s) reference at all,
        # so the page renders from a file:// URL with no network.
        $html | Should-NotMatchString 'https?://'
        $html | Should-NotMatchString '@import'
        $html | Should-NotMatchString '<script'
        $html | Should-NotMatchString '<link'
    }

    It 'draws unresolved targets as pseudo-nodes in the HTML' {
        $html = Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Format Html
        $html | Should-MatchString 'yaml:@ghost/x\.yml'
        $html | Should-MatchString 'stroke-dasharray'
    }

    It 'writes to a path when given one' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) "azdo-graph-$([guid]::NewGuid()).json"
        try {
            Export-AzDoPipelineDependencyGraph -Graph $script:Graph -Path $path
            (Test-Path -LiteralPath $path) | Should-BeTrue
            (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).project | Should-Be 'proj'
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'takes the graph from the pipeline' {
        $json = $script:Graph | Export-AzDoPipelineDependencyGraph -Format Json | ConvertFrom-Json
        $json.project | Should-Be 'proj'
    }
}
