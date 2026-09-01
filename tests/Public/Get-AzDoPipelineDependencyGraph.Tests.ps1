#Requires -Version 7.2
BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    Import-BuiltModule

    $script:OriginalPat = $env:AZDO_PAT
    $env:AZDO_PAT = 'test-token-not-a-real-credential'

    # A synthetic project, served entirely from this mock. It carries the shapes
    # the graph has to get right: an orphan pipeline, a classic definition with
    # no YAML, a template included by two different files, a cycle, a repository
    # that nothing references, an undeclared alias and a missing file.
    #
    # The tables live INSIDE the mock body on purpose. A mock declared with
    # -ModuleName runs in the module's session state, where the test file's
    # $script: variables do not exist - and a null reference in there surfaces
    # as "a 'break' or 'continue' statement escaped from your code" against the
    # whole container, naming nothing that would find it.
    Mock -ModuleName PSAzureDevOpsGraph Invoke-WebRequest {
        $files = @{
            'app/azure-pipelines.yml'     = @"
resources:
  repositories:
    - repository: sharedTemplates
      type: git
      name: shared
    - repository: tools
      type: git
      name: tooling
  pipelines:
    - pipeline: upstream
      source: Upstream-Build
extends:
  template: templates/stages.yml@sharedTemplates
steps:
  - checkout: self
  - checkout: tools
  - template: local/steps.yml
  - template: ghost/x.yml@nope
"@
            'app/local/steps.yml'         = "steps:`n  - template: cycle-a.yml`n"
            'app/local/cycle-a.yml'       = "steps:`n  - template: cycle-b.yml`n"
            'app/local/cycle-b.yml'       = "steps:`n  - template: cycle-a.yml`n"
            'app/orphan.yml'              = "steps:`n  - script: echo nothing`n"
            'shared/templates/stages.yml' = "stages:`n  - template: ../steps/common.yml`n"
            'shared/steps/common.yml'     = "steps:`n  - template: missing.yml`n"
            'shared/up.yml'               = "steps:`n  - template: steps/common.yml`n"
        }

        $definitions = @(
            @{ id = 1; name = 'App-CI'; repo = 'app'; yaml = '/azure-pipelines.yml' }
            @{ id = 2; name = 'Orphan'; repo = 'app'; yaml = '/orphan.yml' }
            @{ id = 3; name = 'Upstream-Build'; repo = 'shared'; yaml = '/up.yml' }
            @{ id = 4; name = 'Classic'; repo = 'app'; yaml = $null }
        )

        $json = $null

        if ($Uri -match '/_apis/git/repositories\?') {
            # 'unused' exists in the project and is referenced by nothing.
            $json = @{ value = @(
                    @{ id = 'r1'; name = 'app'; defaultBranch = 'refs/heads/main'; webUrl = 'x'; isDisabled = $false }
                    @{ id = 'r2'; name = 'shared'; defaultBranch = 'refs/heads/main'; webUrl = 'x'; isDisabled = $false }
                    @{ id = 'r3'; name = 'tooling'; defaultBranch = 'refs/heads/main'; webUrl = 'x'; isDisabled = $false }
                    @{ id = 'r4'; name = 'unused'; defaultBranch = 'refs/heads/main'; webUrl = 'x'; isDisabled = $false }
                ) }
        } elseif ($Uri -match '/_apis/build/definitions/(\d+)\?') {
            $id = [int] $Matches[1]
            $definition = $definitions | Where-Object { $_.id -eq $id }
            $body = @{
                id          = $definition.id
                name        = $definition.name
                repository  = @{ id = 'r'; name = $definition.repo; type = 'TfsGit'; defaultBranch = 'refs/heads/main' }
                queueStatus = 'enabled'
            }
            $body['process'] = if ($definition.yaml) {
                @{ type = 2; yamlFilename = $definition.yaml }
            } else {
                @{ type = 1 }
            }
            $json = $body
        } elseif ($Uri -match '/_apis/build/definitions\?') {
            $json = @{ value = @($definitions | ForEach-Object { @{ id = $_.id; name = $_.name } }) }
        } elseif ($Uri -match '/_apis/git/repositories/([^/]+)/items\?') {
            $repository = [uri]::UnescapeDataString($Matches[1])
            $path = ''
            if ($Uri -match 'path=([^&]+)') { $path = [uri]::UnescapeDataString($Matches[1]).TrimStart('/') }
            $key = "$repository/$path"
            if (-not $files.ContainsKey($key)) {
                # Azure DevOps answers 404 for a path that is not in the
                # repository, and the module must read that as a result.
                $response = [System.Net.Http.HttpResponseMessage]::new(404)
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Not Found', $response)
            }
            $json = @{ path = "/$path"; content = $files[$key] }
        } else {
            throw "The mock was asked for a route the module should never call: $Uri"
        }

        [pscustomobject]@{
            StatusCode = 200
            Content    = ($json | ConvertTo-Json -Depth 20)
            Headers    = @{ 'Content-Type' = 'application/json; charset=utf-8' }
        }
    }

    $script:Graph = Get-AzDoPipelineDependencyGraph -Organisation 'org' -Project 'proj'
    $script:NodeIds = @($script:Graph.nodes | ForEach-Object { $_.id })
}

AfterAll {
    $env:AZDO_PAT = $script:OriginalPat
}

Describe 'Get-AzDoPipelineDependencyGraph' {

    Context 'the shape of the contract' {

        It 'reports version 1 and names the command that produced it' {
            $script:Graph.version | Should-Be 1
            $script:Graph.generatedBy | Should-BeString 'Get-AzDoPipelineDependencyGraph'
        }

        It 'carries the organisation and project it was asked for' {
            $script:Graph.organisation | Should-BeString 'org'
            $script:Graph.project | Should-BeString 'proj'
        }

        It 'gives every yaml node a repo and a path rooted at repos/' {
            foreach ($node in $script:Graph.nodes | Where-Object kind -eq 'yaml') {
                $node.repo | Should-NotBeNull
                $node.path | Should-MatchString '^repos/'
            }
        }

        It 'writes no optional field on a definition edge, which is not about a file' {
            $definition = @($script:Graph.edges | Where-Object kind -eq 'definition')[0]
            $definition.PSObject.Properties.Name | Should-NotContainCollection 'ref'
        }

        It 'sorts nodes and edges so two runs can be diffed' {
            $sorted = @($script:NodeIds | Sort-Object)
            $script:NodeIds | Should-BeCollection $sorted
        }
    }

    Context 'node identity is the thing, never its position' {

        It 'gives a template included by two files one node, not two' {
            @($script:NodeIds | Where-Object { $_ -eq 'yaml:shared/steps/common.yml' }).Count | Should-Be 1
        }

        It 'gives that shared template in-degree 2, because two edges point at one node' {
            $inbound = @($script:Graph.edges | Where-Object { $_.to -eq 'yaml:shared/steps/common.yml' })
            $inbound.Count | Should-Be 2
        }
    }

    Context 'orphans are nodes; unreferenced repositories are not' {

        It 'keeps a pipeline that references nothing and that nothing references' {
            $script:NodeIds | Should-ContainCollection 'pipeline:Orphan'
        }

        It 'keeps a classic definition with no YAML as a node with no definition edge' {
            $script:NodeIds | Should-ContainCollection 'pipeline:Classic'
            @($script:Graph.edges | Where-Object { $_.from -eq 'pipeline:Classic' }).Count | Should-Be 0
        }

        It 'does not emit a node for a repository nothing references' {
            $script:NodeIds | Should-NotContainCollection 'repo:unused'
        }

        It 'does not emit a node for the repository a pipeline merely lives in' {
            # app is never named by resources.repositories or checkout.
            $script:NodeIds | Should-NotContainCollection 'repo:app'
        }

        It 'emits repository nodes for the ones references name' {
            $script:NodeIds | Should-ContainCollection 'repo:shared'
            $script:NodeIds | Should-ContainCollection 'repo:tooling'
        }
    }

    Context 'cycle-safe traversal' {

        It 'terminates and records both edges of the cycle' {
            @($script:Graph.edges | Where-Object {
                    $_.from -eq 'yaml:app/local/cycle-a.yml' -and $_.to -eq 'yaml:app/local/cycle-b.yml'
                }).Count | Should-Be 1
            @($script:Graph.edges | Where-Object {
                    $_.from -eq 'yaml:app/local/cycle-b.yml' -and $_.to -eq 'yaml:app/local/cycle-a.yml'
                }).Count | Should-Be 1
        }
    }

    Context 'unresolved references are the answer the tool exists to give' {

        It 'carries ref, refKind and reason on every unresolved edge' {
            $unresolved = @($script:Graph.edges | Where-Object kind -eq 'unresolved')
            $unresolved.Count | Should-BeGreaterThan 0
            foreach ($edge in $unresolved) {
                $edge.ref | Should-NotBeNull
                $edge.refKind | Should-NotBeNull
                $edge.reason | Should-NotBeNull
            }
        }

        It 'reports an undeclared alias as alias-not-declared, keeping the alias in the target' {
            $edge = @($script:Graph.edges | Where-Object { $_.reason -eq 'alias-not-declared' })
            $edge.Count | Should-Be 1
            $edge[0].to | Should-BeString 'yaml:@nope/ghost/x.yml'
            $edge[0].refKind | Should-BeString 'template'
        }

        It 'reports a missing file as file-not-found, which needs a different fix' {
            $edge = @($script:Graph.edges | Where-Object { $_.reason -eq 'file-not-found' })
            $edge.Count | Should-Be 1
            $edge[0].to | Should-BeString 'yaml:shared/steps/missing.yml'
        }

        It 'gives an unresolved target no node, so it cannot be mistaken for a real one' {
            $script:NodeIds | Should-NotContainCollection 'yaml:@nope/ghost/x.yml'
            $script:NodeIds | Should-NotContainCollection 'yaml:shared/steps/missing.yml'
        }
    }

    Context 'reference kinds are kept apart' {

        It 'records extends as extends, not as template' {
            $edge = @($script:Graph.edges | Where-Object kind -eq 'extends')
            $edge.Count | Should-Be 1
            $edge[0].to | Should-BeString 'yaml:shared/templates/stages.yml'
            $edge[0].ref | Should-BeString 'templates/stages.yml@sharedTemplates'
            $edge[0].alias | Should-BeString 'sharedTemplates'
        }

        It 'records checkout as a repository dependency and invents no template edge from it' {
            $edge = @($script:Graph.edges | Where-Object kind -eq 'checkout')
            $edge.Count | Should-Be 1
            $edge[0].to | Should-BeString 'repo:tooling'
        }

        It 'records a pipelineResource against a definition node' {
            $edge = @($script:Graph.edges | Where-Object kind -eq 'pipelineResource')
            $edge.Count | Should-Be 1
            $edge[0].to | Should-BeString 'pipeline:Upstream-Build'
        }

        It 'resolves a cross-repository relative reference inside that repository' {
            # ../steps/common.yml inside shared/templates/stages.yml stays in
            # shared, not in app where the walk began.
            $edge = @($script:Graph.edges | Where-Object { $_.from -eq 'yaml:shared/templates/stages.yml' })
            $edge[0].to | Should-BeString 'yaml:shared/steps/common.yml'
        }
    }
}
