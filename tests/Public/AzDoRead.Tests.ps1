BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    Import-ModuleUnderTest | Out-Null

    # Input data for the mocked project. A fixture is input, not a module anyone
    # maintains: the two steps-build.yml files, the missing template and the
    # undeclared alias are deliberate and load-bearing.
    $global:AzDoTestCorpus = @{
        Repositories = @(
            @{ id = 'r1'; name = 'pipelines-main'; defaultBranch = 'refs/heads/main' }
            @{ id = 'r2'; name = 'consumer-app'; defaultBranch = 'refs/heads/main' }
            @{ id = 'r3'; name = 'templates-shared'; defaultBranch = 'refs/heads/main' }
            @{ id = 'r4'; name = 'nothing-references-me'; defaultBranch = 'refs/heads/main' }
        )
        Definitions  = @(
            @{ id = 1; name = 'P01'; repository = @{ id = 'r1'; name = 'pipelines-main' }; process = @{ yamlFilename = 'pipelines/p01.yml' } }
            @{ id = 2; name = 'Consumer'; repository = @{ id = 'r2'; name = 'consumer-app' }; process = @{ yamlFilename = 'azure-pipelines.yml' } }
            @{ id = 3; name = 'Orphan'; repository = @{ id = 'r1'; name = 'pipelines-main' }; process = @{ yamlFilename = 'pipelines/orphan.yml' } }
            @{ id = 4; name = 'Cycle'; repository = @{ id = 'r1'; name = 'pipelines-main' }; process = @{ yamlFilename = 'cycle-a.yml' } }
        )
        Files        = @{
            'pipelines-main/pipelines/p01.yml'                    = @'
parameters:
  buildTemplate: templates/steps-build.yml
variables:
  - template: templates/vars-common.yml
steps:
  - checkout: self
  - template: templates/steps-build.yml
  - template: templates/gone.yml
'@
            'pipelines-main/pipelines/templates/vars-common.yml'  = "variables:`n  - name: a`n    value: b`n"
            'pipelines-main/pipelines/templates/steps-build.yml'  = "steps:`n  - script: build, nested copy`n"
            'pipelines-main/templates/steps-build.yml'            = "steps:`n  - script: build, root copy`n"
            'pipelines-main/pipelines/orphan.yml'                 = "steps:`n  - script: references nothing`n"
            'pipelines-main/cycle-a.yml'                          = "steps:`n  - template: cycle-b.yml`n"
            'pipelines-main/cycle-b.yml'                          = "steps:`n  - template: cycle-a.yml`n  - template: pipelines/templates/steps-build.yml`n"
            'consumer-app/azure-pipelines.yml'                    = @'
resources:
  repositories:
    - repository: mainPipelines
      type: git
      name: ClaudeTesting/pipelines-main
extends:
  template: templates/steps-build.yml@mainPipelines
steps:
  - checkout: mainPipelines
  - template: steps/common.yml@ghostTemplates
'@
        }
    }
}

AfterAll {
    Remove-Variable -Name AzDoTestCorpus -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Reading Azure DevOps' {

    BeforeAll {
        Mock -ModuleName PSAzureDevOpsGraph -CommandName Invoke-WebRequest -MockWith {
            $corpus = $global:AzDoTestCorpus
            $url = [string] $Uri

            if ($url -match '/_apis/git/repositories/([^/?]+)/items') {
                $repository = [uri]::UnescapeDataString($Matches[1])
                $path = ''
                if ($url -match '[?&]path=([^&]*)') { $path = [uri]::UnescapeDataString($Matches[1]).TrimStart('/') }
                $key = "$repository/$path"
                if (-not $corpus.Files.ContainsKey($key)) {
                    $message = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::NotFound)
                    throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('404 (Not Found)', $message)
                }
                return New-AzDoWebResponse -Body @{ path = "/$path"; content = $corpus.Files[$key] }
            }
            if ($url -match '/_apis/build/definitions/(\d+)') {
                $id = [int] $Matches[1]
                return New-AzDoWebResponse -Body ($corpus.Definitions | Where-Object { $_.id -eq $id })
            }
            if ($url -match '/_apis/build/definitions') {
                return New-AzDoWebResponse -Body @{ count = $corpus.Definitions.Count; value = $corpus.Definitions }
            }
            if ($url -match '/_apis/git/repositories') {
                return New-AzDoWebResponse -Body @{ count = $corpus.Repositories.Count; value = $corpus.Repositories }
            }
            throw "The test corpus has no route for $url"
        }
    }

    Context 'Get-AzDoRepository' {
        It 'lists the repositories in the project' {
            $repositories = @(Get-AzDoRepository -Organisation org -Project proj)
            $repositories.Count | Should-Be 4
            $repositories[0].Name | Should-Be 'pipelines-main'
        }

        It 'filters by name' {
            $repository = Get-AzDoRepository -Organisation org -Project proj -Name 'consumer-app'
            $repository.Id | Should-Be 'r2'
        }
    }

    Context 'Get-AzDoPipeline' {
        It 'fetches each definition by id, because the list form carries no yaml path' {
            $definitions = @(Get-AzDoPipeline -Organisation org -Project proj)
            $definitions.Count | Should-Be 4
            ($definitions | Where-Object Name -EQ 'P01').YamlPath | Should-Be 'pipelines/p01.yml'
            ($definitions | Where-Object Name -EQ 'P01').RepositoryName | Should-Be 'pipelines-main'
        }

        It 'fetches one definition by id' {
            (Get-AzDoPipeline -Organisation org -Project proj -Id 2).Name | Should-Be 'Consumer'
        }
    }

    Context 'Get-AzDoPipelineYaml' {
        It 'returns the text of a path in a repository' {
            Get-AzDoPipelineYaml -Organisation org -Project proj -Repository pipelines-main -Path cycle-a.yml |
                Should-MatchString 'cycle-b.yml'
        }

        It 'returns the text for a definition' {
            Get-AzDoPipelineYaml -Organisation org -Project proj -DefinitionId 3 | Should-MatchString 'references nothing'
        }

        It 'returns null for a file that is not there, because that is a result and not an error' {
            $text = Get-AzDoPipelineYaml -Organisation org -Project proj -Repository pipelines-main -Path no/such.yml
            ($null -eq $text) | Should-BeTrue
        }
    }

    Context 'Get-AzDoPipelineDependencyGraph' {

        BeforeAll {
            $script:Graph = Get-AzDoPipelineDependencyGraph -Organisation org -Project proj -WarningAction SilentlyContinue
            $script:NodeIds = @($script:Graph.nodes | ForEach-Object { $_.id })
            $script:EdgeKeys = @($script:Graph.edges | ForEach-Object { "$($_.from)|$($_.to)|$($_.kind)" })
        }

        It 'validates as version 1 and names the command that produced it' {
            $script:Graph.version | Should-Be 1
            $script:Graph.generatedBy | Should-Be 'Get-AzDoPipelineDependencyGraph'
        }

        It 'keeps a pipeline that references nothing, joined to its yaml by a definition edge' {
            $script:NodeIds | Should-ContainCollection -Expected 'pipeline:Orphan'
            $script:EdgeKeys | Should-ContainCollection -Expected 'pipeline:Orphan|yaml:pipelines-main/pipelines/orphan.yml|definition'
        }

        It 'excludes a repository nothing references' {
            $script:NodeIds | Should-NotContainCollection -Expected 'repo:nothing-references-me'
            $script:NodeIds | Should-NotContainCollection -Expected 'repo:templates-shared'
        }

        It 'includes a repository a checkout or a resource references' {
            $script:NodeIds | Should-ContainCollection -Expected 'repo:pipelines-main'
        }

        It 'resolves the two rules to two different files from the same reference text' {
            # pipelines/p01.yml says templates/steps-build.yml with no alias;
            # consumer-app says templates/steps-build.yml@mainPipelines. Same
            # text, different files.
            $script:NodeIds | Should-ContainCollection -Expected 'yaml:pipelines-main/pipelines/templates/steps-build.yml'
            $script:NodeIds | Should-ContainCollection -Expected 'yaml:pipelines-main/templates/steps-build.yml'
        }

        It 'gives one node to a template two files include' {
            $shared = @($script:Graph.nodes | Where-Object { $_.id -eq 'yaml:pipelines-main/pipelines/templates/steps-build.yml' })
            $shared.Count | Should-Be 1
            $inbound = @($script:Graph.edges | Where-Object { $_.to -eq 'yaml:pipelines-main/pipelines/templates/steps-build.yml' })
            $inbound.Count | Should-Be 2
        }

        It 'records both edges of a cycle and still terminates' {
            $script:EdgeKeys | Should-ContainCollection -Expected 'yaml:pipelines-main/cycle-a.yml|yaml:pipelines-main/cycle-b.yml|template'
            $script:EdgeKeys | Should-ContainCollection -Expected 'yaml:pipelines-main/cycle-b.yml|yaml:pipelines-main/cycle-a.yml|template'
        }

        It 'carries an extends edge as extends, not as template' {
            $extends = @($script:Graph.edges | Where-Object { $_.kind -eq 'extends' })
            $extends.Count | Should-Be 1
            $extends[0].to | Should-Be 'yaml:pipelines-main/templates/steps-build.yml'
            $extends[0].ref | Should-Be 'templates/steps-build.yml@mainPipelines'
        }

        It 'invents no template edge from a checkout' {
            $checkout = @($script:Graph.edges | Where-Object { $_.kind -eq 'checkout' })
            $checkout.Count | Should-Be 1
            $checkout[0].to | Should-Be 'repo:pipelines-main'
        }

        It 'keeps an unresolved reference as a result carrying a reason' {
            $unresolved = @($script:Graph.edges | Where-Object { $_.kind -eq 'unresolved' })
            $unresolved.Count | Should-Be 2
            @($unresolved.reason | Sort-Object) | Should-BeCollection -Expected @('alias-not-declared', 'file-not-found')
        }

        It 'keeps an undeclared alias in the unresolved target id so it cannot collide with a real node' {
            $ghost = @($script:Graph.edges | Where-Object { $_.reason -eq 'alias-not-declared' })
            $ghost[0].to | Should-Be 'yaml:@ghostTemplates/steps/common.yml'
            $script:NodeIds | Should-NotContainCollection -Expected 'yaml:@ghostTemplates/steps/common.yml'
        }

        It 'gives every unresolved edge a ref, a refKind and a reason' {
            foreach ($edge in @($script:Graph.edges | Where-Object { $_.kind -eq 'unresolved' })) {
                $edge.ref | Should-NotBeNull
                $edge.refKind | Should-NotBeNull
                $edge.reason | Should-NotBeNull
            }
        }

        It 'gives every yaml node a repo and a path under repos/' {
            foreach ($node in @($script:Graph.nodes | Where-Object { $_.kind -eq 'yaml' })) {
                $node.repo | Should-NotBeNull
                $node.path | Should-MatchString '^repos/'
            }
        }

        It 'invents no reference from buildTemplate in the live document' {
            @($script:Graph.edges | Where-Object { $_.to -eq 'yaml:pipelines-main/pipelines/templates/steps-build.yml' -and $_.from -eq 'yaml:pipelines-main/pipelines/p01.yml' }).Count |
                Should-Be 1
        }

        It 'sorts nodes and edges so two runs diff to nothing' {
            $sorted = @($script:NodeIds | Sort-Object)
            @($script:NodeIds) | Should-BeCollection -Expected $sorted
        }
    }
}

Describe 'Paging' {
    It 'follows the continuation token in the response header' {
        $script:Call = 0
        Mock -ModuleName PSAzureDevOpsGraph -CommandName Invoke-WebRequest -MockWith {
            $script:Call++
            if ($script:Call -eq 1) {
                New-AzDoWebResponse -Body @{ value = @(@{ id = 'a'; name = 'first' }) } -ContinuationToken 'page2'
            } else {
                New-AzDoWebResponse -Body @{ value = @(@{ id = 'b'; name = 'second' }) }
            }
        }

        $repositories = @(Get-AzDoRepository -Organisation org -Project proj)
        $repositories.Count | Should-Be 2
        $script:Call | Should-Be 2
    }
}

Describe 'The credential rule' {
    It 'fails by naming the variable when AZDO_PAT is absent' {
        $saved = $env:AZDO_PAT
        try {
            $env:AZDO_PAT = ''
            { Get-AzDoRepository -Organisation org -Project proj } | Should-Throw -ExceptionMessage '*AZDO_PAT*'
        } finally {
            $env:AZDO_PAT = $saved
        }
    }

    It 'takes no credential parameter on any exported command' {
        foreach ($command in (Get-Command -Module PSAzureDevOpsGraph)) {
            foreach ($forbidden in 'Pat', 'Token', 'Credential', 'PatPath', 'Password') {
                $command.Parameters.Keys | Should-NotContainCollection -Expected $forbidden
            }
        }
    }
}
