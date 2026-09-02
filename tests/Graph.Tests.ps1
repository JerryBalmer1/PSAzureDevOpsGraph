#Requires -Version 7.2
<#
    End-to-end tests for the commands that talk to Azure DevOps.

    The transport is mocked at Invoke-AzDoRestMethod, which is the single point
    every request in the module goes through. Mocking there rather than at
    Invoke-RestMethod keeps the tests about this module's behaviour instead of
    about URL construction, and it means no credential and no network are needed
    to exercise the whole walk.
#>

BeforeAll {
    . "$PSScriptRoot/Import-ModuleUnderTest.ps1"

    $script:DemoYaml = @'
resources:
  repositories:
    - repository: sharedRepo
      type: git
      name: Proj/shared
  pipelines:
    - pipeline: upstream
      source: demo
steps:
  - checkout: self
  - checkout: sharedRepo
  - template: templates/local.yml
  - template: steps/common.yml@sharedRepo
  - template: templates/missing.yml
  - template: steps/x.yml@ghost
'@

    $script:Files = @{
        'id-app|/pipelines/demo.yml'            = $script:DemoYaml
        'id-app|/pipelines/templates/local.yml' = "steps:`n  - script: echo local"
        'id-shared|/steps/common.yml'           = "steps:`n  - script: echo common"
    }

    Mock -ModuleName PSAzureDevOpsGraph -CommandName Invoke-AzDoRestMethod -MockWith {
        switch -Regex ($ApiPath) {
            '^git/repositories$' {
                return [pscustomobject]@{ value = @(
                        [pscustomobject]@{ id = 'id-app'; name = 'app'; defaultBranch = 'refs/heads/main'; size = 10; webUrl = 'https://example/app' }
                        [pscustomobject]@{ id = 'id-shared'; name = 'shared'; defaultBranch = 'refs/heads/main'; size = 10; webUrl = 'https://example/shared' }
                        # No defaultBranch property at all -- a repository with no
                        # commits. Reading it directly would throw under StrictMode.
                        [pscustomobject]@{ id = 'id-unused'; name = 'unused' }
                    ) }
            }
            '^build/definitions$' {
                return [pscustomobject]@{ value = @(
                        [pscustomobject]@{
                            id = 1; name = 'demo'; path = '\'; revision = 1
                            repository = [pscustomobject]@{ id = 'id-app'; name = 'app'; type = 'TfsGit' }
                            process    = [pscustomobject]@{ yamlFilename = 'pipelines/demo.yml'; type = 2 }
                        }
                        # A classic (non-YAML) definition: it is a pipeline, but it
                        # has no YAML file to walk.
                        [pscustomobject]@{
                            id = 2; name = 'classic'; path = '\'; revision = 1
                            repository = [pscustomobject]@{ id = 'id-app'; name = 'app'; type = 'TfsGit' }
                            process    = [pscustomobject]@{ type = 1 }
                        }
                    ) }
            }
            '^git/repositories/(?<repo>[^/]+)/items$' {
                $key = '{0}|{1}' -f $Matches['repo'], $Query['path']
                if ($script:Files.ContainsKey($key)) {
                    return [pscustomobject]@{ path = $Query['path']; content = $script:Files[$key] }
                }
                throw "404 not found: $key"
            }
        }
        throw "unexpected ApiPath: $ApiPath"
    }
}

Describe 'Get-AzDoRepository' {

    It 'returns every repository, including one with no commits' {
        $repos = @(Get-AzDoRepository -Organisation o -Project p)
        $repos.Count | Should-Be 3
        @($repos.Name | Sort-Object) | Should-BeCollection @('app', 'shared', 'unused')
    }

    It 'marks a repository with no default branch as empty' {
        $repo = Get-AzDoRepository -Organisation o -Project p -Name 'unused'
        $repo.IsEmpty       | Should-BeTrue
        $repo.DefaultBranch | Should-BeFalsy
    }

    It 'filters by name' {
        @(Get-AzDoRepository -Organisation o -Project p -Name 'app').Count | Should-Be 1
    }
}

Describe 'Get-AzDoPipeline' {

    It 'returns each definition with the repository and path its YAML lives at' {
        $demo = Get-AzDoPipeline -Organisation o -Project p -Name 'demo'
        $demo.Repository | Should-Be 'app'
        $demo.Path       | Should-Be 'pipelines/demo.yml'
        $demo.IsYaml     | Should-BeTrue
    }

    It 'reports a classic definition as having no YAML' {
        $classic = Get-AzDoPipeline -Organisation o -Project p -Name 'classic'
        $classic.IsYaml | Should-BeFalse
        $classic.Path   | Should-BeFalsy
    }
}

Describe 'Get-AzDoPipelineYaml' {

    It 'returns the text of a path in a repository' {
        $doc = Get-AzDoPipelineYaml -Organisation o -Project p -Repository app -Path 'pipelines/templates/local.yml'
        $doc.Found | Should-BeTrue
        $doc.Yaml  | Should-MatchString 'echo local'
    }

    It 'reports a missing file rather than throwing' {
        $doc = Get-AzDoPipelineYaml -Organisation o -Project p -Repository app -Path 'pipelines/templates/missing.yml'
        $doc.Found  | Should-BeFalse
        $doc.Reason | Should-MatchString 'not found'
    }

    It 'reports a missing repository rather than throwing' {
        $doc = Get-AzDoPipelineYaml -Organisation o -Project p -Repository absent -Path 'a.yml'
        $doc.Found  | Should-BeFalse
        $doc.Reason | Should-MatchString "repository 'absent' not found"
    }

    It 'takes a definition from the pipeline' {
        $doc = Get-AzDoPipeline -Organisation o -Project p -Name 'demo' |
            Get-AzDoPipelineYaml -Organisation o -Project p
        $doc.Path | Should-Be 'pipelines/demo.yml'
    }
}

Describe 'Get-AzDoPipelineDependencyGraph' {

    BeforeAll {
        $script:Graph = Get-AzDoPipelineDependencyGraph -Organisation o -Project p
        $script:NodeIds = @($script:Graph.nodes | ForEach-Object { $_.id })
        $script:Edges = $script:Graph.edges
    }

    It 'declares the shape the schema requires' {
        $Graph.version      | Should-Be 1
        $Graph.organisation | Should-Be 'o'
        $Graph.project      | Should-Be 'p'
        $Graph.generatedBy  | Should-Be 'Get-AzDoPipelineDependencyGraph'
    }

    It 'has a node for every pipeline definition, YAML or not' {
        $NodeIds | Should-ContainCollection 'pipeline:demo'
        $NodeIds | Should-ContainCollection 'pipeline:classic'
    }

    It 'records the repository a pipeline is registered against' {
        ($Graph.nodes | Where-Object { $_.id -eq 'pipeline:demo' }).repo | Should-Be 'app'
    }

    It 'gives a yaml node a fixture-rooted path and its repository' {
        $node = $Graph.nodes | Where-Object { $_.id -eq 'yaml:app/pipelines/demo.yml' }
        $node.kind | Should-Be 'yaml'
        $node.repo | Should-Be 'app'
        $node.path | Should-Be 'repos/app/pipelines/demo.yml'
    }

    It 'includes a repository that takes part and excludes one that does not' {
        $NodeIds | Should-ContainCollection 'repo:app'
        $NodeIds | Should-ContainCollection 'repo:shared'
        $NodeIds | Should-NotContainCollection 'repo:unused'
    }

    It 'joins a pipeline to its YAML with a definition edge' {
        $edge = $Edges | Where-Object { $_.kind -eq 'definition' -and $_.from -eq 'pipeline:demo' }
        $edge.to | Should-Be 'yaml:app/pipelines/demo.yml'
    }

    It 'resolves an unaliased template against the referring directory' {
        @($Edges | Where-Object { $_.to -eq 'yaml:app/pipelines/templates/local.yml' }).Count | Should-Be 1
    }

    It 'resolves an aliased template from the root of the aliased repository' {
        @($Edges | Where-Object { $_.to -eq 'yaml:shared/steps/common.yml' }).Count | Should-Be 1
    }

    It 'makes no edge for checkout self' {
        @($Edges | Where-Object { $_.kind -eq 'checkout' -and $_.to -eq 'repo:app' }).Count | Should-Be 0
    }

    It 'makes an edge for checkout of another repository' {
        @($Edges | Where-Object { $_.kind -eq 'checkout' -and $_.to -eq 'repo:shared' }).Count | Should-Be 1
    }

    It 'records an alias where it is declared and not where it is used' {
        ($Edges | Where-Object { $_.kind -eq 'repositoryResource' }).alias | Should-Be 'sharedRepo'
        ($Edges | Where-Object { $_.kind -eq 'pipelineResource' }).alias   | Should-Be 'upstream'
        $used = $Edges | Where-Object { $_.kind -eq 'template' -and $_.ref -eq 'steps/common.yml@sharedRepo' }
        $used.Contains('alias') | Should-BeFalse
    }

    It 'reports a missing file as unresolved, pointing where it should have been' {
        $edge = $Edges | Where-Object { $_.kind -eq 'unresolved' -and $_.to -eq 'yaml:app/pipelines/templates/missing.yml' }
        $edge.reason  | Should-MatchString '^file-not-found: resolved to pipelines/templates/missing\.yml in app'
        $edge.refKind | Should-Be 'template'
    }

    It 'reports an undeclared alias as unresolved, naming the alias in the target' {
        $edge = $Edges | Where-Object { $_.kind -eq 'unresolved' -and $_.to -eq 'yaml:@ghost/steps/x.yml' }
        $edge.reason | Should-MatchString "^alias-not-declared: 'ghost' is not in resources\.repositories"
    }

    It 'drops no reference: every one in the document becomes an edge' {
        # Eight references in demo.yml -- one repository resource, one pipeline
        # resource, two checkouts and four templates -- minus 'checkout: self',
        # which is not a dependency on anything the file does not already have.
        @($Edges | Where-Object { $_.from -eq 'yaml:app/pipelines/demo.yml' }).Count | Should-Be 7
    }
}

Describe 'Export-AzDoPipelineDependencyGraph' {

    BeforeAll {
        $script:Graph = Get-AzDoPipelineDependencyGraph -Organisation o -Project p
    }

    It 'writes JSON that round-trips to the same nodes and edges' {
        $path = Join-Path $TestDrive 'graph.json'
        $Graph | Export-AzDoPipelineDependencyGraph -Format Json -Path $path
        $back = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $back.version     | Should-Be 1
        $back.nodes.Count | Should-Be $Graph.nodes.Count
        $back.edges.Count | Should-Be $Graph.edges.Count
    }

    It 'writes JSON with LF endings and a trailing newline, because it is diffed' {
        $path = Join-Path $TestDrive 'lf.json'
        $Graph | Export-AzDoPipelineDependencyGraph -Format Json -Path $path
        $bytes = [System.IO.File]::ReadAllBytes($path)
        ($bytes -contains 13) | Should-BeFalse
        $bytes[-1]            | Should-Be 10
    }

    It 'returns the text when no path is given' {
        $text = $Graph | Export-AzDoPipelineDependencyGraph -Format Dot
        $text | Should-MatchString '^digraph PipelineDependencies \{'
        $text | Should-MatchString 'yaml:app/pipelines/demo\.yml'
    }

    It 'writes self-contained HTML with no external reference' {
        $path = Join-Path $TestDrive 'graph.html'
        $Graph | Export-AzDoPipelineDependencyGraph -Format Html -Path $path
        $html = Get-Content -LiteralPath $path -Raw
        $html | Should-MatchString '<!DOCTYPE html>'
        $html | Should-NotMatchString '(?i)<script[^>]+src='
        $html | Should-NotMatchString '(?i)<link[^>]+href='
    }

    It 'creates the directory it is asked to write into' {
        $path = Join-Path $TestDrive 'nested' 'deeper' 'graph.json'
        $Graph | Export-AzDoPipelineDependencyGraph -Format Json -Path $path
        (Test-Path -LiteralPath $path) | Should-BeTrue
    }
}
