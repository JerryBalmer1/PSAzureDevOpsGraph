#Requires -Version 7.2

BeforeAll {
    . "$PSScriptRoot/Import-ModuleUnderTest.ps1"
}

Describe 'Get-AzDoPipelineReference' {

    It 'finds a same-repo step template' {
        $refs = @(Get-AzDoPipelineReference -Yaml @'
steps:
  - template: templates/steps-build.yml
'@)
        $refs.Count    | Should-Be 1
        $refs[0].Kind  | Should-Be 'template'
        $refs[0].Path  | Should-Be 'templates/steps-build.yml'
        $refs[0].Alias | Should-BeFalsy
    }

    It 'separates an aliased path from its alias' {
        $refs = @(Get-AzDoPipelineReference -Yaml @'
steps:
  - template: steps/common.yml@sharedTemplates
'@)
        $refs[0].Path      | Should-Be 'steps/common.yml'
        $refs[0].Alias     | Should-Be 'sharedTemplates'
        $refs[0].Reference | Should-Be 'steps/common.yml@sharedTemplates'
    }

    It 'reports extends as extends, not as template' {
        $refs = @(Get-AzDoPipelineReference -Yaml @'
extends:
  template: jobs/release.yml@platformTemplates
  parameters:
    environment: staging
'@)
        $refs.Count   | Should-Be 1
        $refs[0].Kind | Should-Be 'extends'
    }

    It 'does not follow a parameter whose value merely looks like a template path' {
        $refs = @(Get-AzDoPipelineReference -Yaml @'
extends:
  template: jobs/release.yml@platformTemplates
  parameters:
    buildTemplate: templates/steps-build.yml
'@)
        $refs.Count        | Should-Be 1
        $refs[0].Reference | Should-Be 'jobs/release.yml@platformTemplates'
    }

    It 'reads a repository resource with its alias and name' {
        $refs = @(Get-AzDoPipelineReference -Yaml @'
resources:
  repositories:
    - repository: sharedTemplates
      type: git
      name: ClaudeTesting/templates-shared
'@)
        $refs.Count    | Should-Be 1
        $refs[0].Kind  | Should-Be 'repositoryResource'
        $refs[0].Alias | Should-Be 'sharedTemplates'
        $refs[0].Name  | Should-Be 'ClaudeTesting/templates-shared'
    }

    It 'reads two repository resources in one block as two references' {
        $refs = @(Get-AzDoPipelineReference -Yaml @'
resources:
  repositories:
    - repository: sharedTemplates
      type: git
      name: ClaudeTesting/templates-shared
    - repository: platformTemplates
      type: git
      name: ClaudeTesting/templates-platform
'@)
        $refs.Count      | Should-Be 2
        @($refs.Alias)   | Should-BeCollection @('sharedTemplates', 'platformTemplates')
    }

    It 'reads a pipeline resource' {
        $refs = @(Get-AzDoPipelineReference -Yaml @'
resources:
  pipelines:
    - pipeline: upstreamBuild
      source: p01-simple-include
      trigger:
        branches:
          include:
            - main
'@)
        $refs.Count     | Should-Be 1
        $refs[0].Kind   | Should-Be 'pipelineResource'
        $refs[0].Source | Should-Be 'p01-simple-include'
        $refs[0].Alias  | Should-Be 'upstreamBuild'
    }

    It 'reads checkout, and treats self as having no alias' {
        $refs = @(Get-AzDoPipelineReference -Yaml @'
steps:
  - checkout: self
  - checkout: sharedTemplates
'@)
        $refs.Count    | Should-Be 2
        $refs[0].Alias | Should-BeFalsy
        $refs[1].Alias | Should-Be 'sharedTemplates'
    }

    It 'finds a template in the variables block' {
        $refs = @(Get-AzDoPipelineReference -Yaml @'
variables:
  - template: templates/vars-common.yml
  - name: buildConfiguration
    value: Release
'@)
        $refs.Count   | Should-Be 1
        $refs[0].Kind | Should-Be 'template'
    }

    It 'ignores a commented-out reference' {
        $refs = @(Get-AzDoPipelineReference -Yaml @'
steps:
  # - template: templates/not-real.yml
  - script: echo hello
'@)
        $refs.Count | Should-Be 0
    }

    It 'keeps a hash that is not a comment' {
        $refs = @(Get-AzDoPipelineReference -Yaml @'
resources:
  repositories:
    - repository: r
      name: Proj/Repo
      ref: refs/heads/feature#1
'@)
        $refs[0].Ref | Should-Be 'refs/heads/feature#1'
    }

    It 'returns nothing for an empty document' {
        @(Get-AzDoPipelineReference -Yaml '').Count | Should-Be 0
    }

    It 'reads a document from a file and carries its provenance' {
        $path = Join-Path $TestDrive 'azure-pipelines.yml'
        Set-Content -LiteralPath $path -Value "steps:`n  - template: templates/a.yml"
        $refs = @(Get-AzDoPipelineReference -Path $path)
        $refs.Count      | Should-Be 1
        $refs[0].SourcePath | Should-Be $path
    }

    It 'refuses a file that is not there' {
        Should-Throw -ScriptBlock { Get-AzDoPipelineReference -Path (Join-Path $TestDrive 'nope.yml') }
    }
}

Describe 'Resolve-AzDoPipelineReference' {

    It 'resolves an unaliased path relative to the referring file' {
        $ref = [pscustomobject]@{ Kind = 'template'; Reference = 'templates/steps-build.yml'; Path = 'templates/steps-build.yml'; Alias = $null; Line = 1 }
        $r = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository pipelines-main -SourcePath 'pipelines/p01.yml'
        $r.Resolved   | Should-BeTrue
        $r.Repository | Should-Be 'pipelines-main'
        $r.Path       | Should-Be 'pipelines/templates/steps-build.yml'
    }

    It 'resolves an aliased path from the root of the aliased repository' {
        $ref = [pscustomobject]@{ Kind = 'template'; Reference = 'templates/steps-build.yml@mainPipelines'; Path = 'templates/steps-build.yml'; Alias = 'mainPipelines'; Line = 1 }
        $r = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository consumer-app -SourcePath 'azure-pipelines.yml' -Alias @{ mainPipelines = 'pipelines-main' }
        $r.Repository | Should-Be 'pipelines-main'
        $r.Path       | Should-Be 'templates/steps-build.yml'
    }

    It 'gives the two rules different answers for the same path' {
        $ref = [pscustomobject]@{ Kind = 'template'; Reference = 'x'; Path = 'templates/steps-build.yml'; Alias = $null; Line = 1 }
        $relative = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository pipelines-main -SourcePath 'pipelines/p01.yml'
        $ref2 = [pscustomobject]@{ Kind = 'template'; Reference = 'x'; Path = 'templates/steps-build.yml'; Alias = 'mainPipelines'; Line = 1 }
        $rooted = Resolve-AzDoPipelineReference -Reference $ref2 -SourceRepository pipelines-main -SourcePath 'pipelines/p01.yml' -Alias @{ mainPipelines = 'pipelines-main' }
        $relative.Path | Should-NotBe $rooted.Path
    }

    It 'walks up with ..' {
        $ref = [pscustomobject]@{ Kind = 'template'; Reference = '../steps/common.yml'; Path = '../steps/common.yml'; Alias = $null; Line = 1 }
        $r = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository templates-shared -SourcePath 'pipelines/nightly.yml'
        $r.Path | Should-Be 'steps/common.yml'
    }

    It 'anchors a leading slash at the repository root' {
        $ref = [pscustomobject]@{ Kind = 'template'; Reference = '/templates/a.yml'; Path = '/templates/a.yml'; Alias = $null; Line = 1 }
        $r = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository app -SourcePath 'deep/nested/file.yml'
        $r.Path | Should-Be 'templates/a.yml'
    }

    It 'reports an undeclared alias rather than guessing' {
        $ref = [pscustomobject]@{ Kind = 'template'; Reference = 'steps/common.yml@ghostTemplates'; Path = 'steps/common.yml'; Alias = 'ghostTemplates'; Line = 1 }
        $r = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository pipelines-main -SourcePath 'pipelines/p09.yml' -Alias @{ sharedTemplates = 'templates-shared' }
        $r.Resolved   | Should-BeFalse
        # The reason names the token first so it can be grouped on, then says
        # enough that the edge can be acted on without re-reading the YAML.
        $r.Reason     | Should-MatchString "^alias-not-declared: 'ghostTemplates' is not in resources\.repositories of pipelines/p09\.yml"
        $r.Repository | Should-Be '@ghostTemplates'
        $r.Path       | Should-Be 'steps/common.yml'
    }

    It 'takes the repository name from a Project/Repository resource name' {
        $ref = [pscustomobject]@{ Kind = 'repositoryResource'; Reference = 'ClaudeTesting/templates-shared'; Name = 'ClaudeTesting/templates-shared'; Alias = 'sharedTemplates'; Line = 1 }
        $r = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository pipelines-main -SourcePath 'pipelines/p09.yml'
        $r.Repository | Should-Be 'templates-shared'
        $r.TargetKind | Should-Be 'repo'
    }

    It 'reports a repository resource that names a repository the project does not have' {
        $ref = [pscustomobject]@{ Kind = 'repositoryResource'; Reference = 'Proj/absent'; Name = 'Proj/absent'; Alias = 'a'; Line = 1 }
        $r = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository app -SourcePath 'a.yml' -KnownRepository @('app')
        $r.Resolved | Should-BeFalse
        $r.Reason   | Should-MatchString 'repository-not-found'
    }

    It 'reports a pipeline resource whose source does not exist' {
        $ref = [pscustomobject]@{ Kind = 'pipelineResource'; Reference = 'absent'; Source = 'absent'; Alias = 'up'; Line = 1 }
        $r = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository app -SourcePath 'a.yml' -KnownPipeline @('present')
        $r.Resolved | Should-BeFalse
        $r.Reason   | Should-MatchString 'pipeline-not-found'
    }

    It 'points checkout self at the repository of the referring file' {
        $ref = [pscustomobject]@{ Kind = 'checkout'; Reference = 'self'; Alias = $null; Line = 1 }
        $r = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository consumer-app -SourcePath 'azure-pipelines.yml'
        $r.Repository | Should-Be 'consumer-app'
    }

    It 'reads a repository out of a git:// checkout' {
        $ref = [pscustomobject]@{ Kind = 'checkout'; Reference = 'git://Proj/other@refs/heads/main'; Alias = 'git://Proj/other@refs/heads/main'; Line = 1 }
        $r = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository app -SourcePath 'a.yml'
        $r.Repository | Should-Be 'other'
    }

    It 'emits nothing for checkout none' {
        $ref = [pscustomobject]@{ Kind = 'checkout'; Reference = 'none'; Alias = $null; Line = 1 }
        @(Resolve-AzDoPipelineReference -Reference $ref -SourceRepository consumer-app -SourcePath 'azure-pipelines.yml').Count |
            Should-Be 0
    }
}

Describe 'Authentication' {

    It 'names the environment variable when it is absent' {
        $saved = $env:AZDO_PAT
        try {
            $env:AZDO_PAT = ''
            Should-Throw -ScriptBlock { Get-AzDoRepository -Organisation o -Project p } -ExceptionMessage '*AZDO_PAT*'
        }
        finally { $env:AZDO_PAT = $saved }
    }

    It 'exposes no parameter that could carry a token' {
        # Anchored at the end so that 'Path' is not read as 'Pat'.
        $offenders = @(
            foreach ($command in (Get-Command -Module PSAzureDevOpsGraph)) {
                $command.Parameters.Keys |
                    Where-Object { $_ -match '(?i)(pat|token|password|credential|secret|apikey)$' } |
                    ForEach-Object { "$($command.Name) -$_" }
            }
        )
        $offenders.Count | Should-Be 0 -Because 'a credential must never arrive as a parameter value'
    }
}

Describe 'Read-only by construction' {

    It 'exports no command whose verb writes' {
        $writing = 'New', 'Set', 'Remove', 'Start', 'Invoke', 'Add', 'Update', 'Clear', 'Delete', 'Stop', 'Restart'
        foreach ($command in (Get-Command -Module PSAzureDevOpsGraph)) {
            $verb = ($command.Name -split '-')[0]
            ($writing -contains $verb) | Should-BeFalse -Because "$($command.Name) must not be a writing verb"
        }
    }

    It 'issues no HTTP verb other than GET' {
        $source = Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'src') -Filter '*.ps1' -Recurse |
            Get-Content -Raw
        ($source -join "`n") | Should-NotMatchString "-Method\s+'?(Post|Put|Patch|Delete)"
    }
}
