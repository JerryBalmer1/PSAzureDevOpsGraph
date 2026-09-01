#Requires -Version 7.2
BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    Import-BuiltModule

    function New-Reference {
        param($Kind, $Reference, $Alias, $Name, $Type)
        $refs = @(Get-AzDoPipelineReference -Content @"
steps:
  - template: $Reference
"@)
        $refs[0]
    }
}

Describe 'Resolve-AzDoPipelineReference' {

    Context 'no @alias - relative to the directory of the including file' {

        It 'resolves against the referencing file directory, not the repository root' {
            $ref = @(Get-AzDoPipelineReference -Content "steps:`n  - template: templates/steps-build.yml`n")[0]
            $result = Resolve-AzDoPipelineReference -Reference $ref `
                -SourceRepository 'pipelines-main' -SourcePath 'pipelines/p01.yml'

            $result.Resolved | Should-BeTrue
            $result.Repository | Should-BeString 'pipelines-main'
            $result.Path | Should-BeString 'pipelines/templates/steps-build.yml'
            $result.TargetId | Should-BeString 'yaml:pipelines-main/pipelines/templates/steps-build.yml'
        }

        It 'normalises a parent-directory reference' {
            $ref = @(Get-AzDoPipelineReference -Content "steps:`n  - template: ../shared/steps-lint.yml`n")[0]
            $result = Resolve-AzDoPipelineReference -Reference $ref `
                -SourceRepository 'consumer-app' -SourcePath 'pipelines/nested/p.yml'
            $result.Path | Should-BeString 'pipelines/shared/steps-lint.yml'
        }

        It 'keeps the current repository as a property of the file, not of the walk' {
            $ref = @(Get-AzDoPipelineReference -Content "steps:`n  - template: notify.yml`n")[0]
            $result = Resolve-AzDoPipelineReference -Reference $ref `
                -SourceRepository 'templates-shared' -SourcePath 'steps/common.yml'
            $result.Repository | Should-BeString 'templates-shared'
            $result.Path | Should-BeString 'steps/notify.yml'
        }
    }

    Context 'with @alias - from the root of the aliased repository' {

        It 'joins the path to the repository root and ignores the source directory' {
            $ref = @(Get-AzDoPipelineReference -Content "steps:`n  - template: templates/steps-build.yml@mainPipelines`n")[0]
            $result = Resolve-AzDoPipelineReference -Reference $ref `
                -SourceRepository 'consumer-app' -SourcePath 'deep/nested/azure-pipelines.yml' `
                -Alias @{ mainPipelines = 'pipelines-main' }

            $result.Resolved | Should-BeTrue
            $result.Repository | Should-BeString 'pipelines-main'
            $result.Path | Should-BeString 'templates/steps-build.yml'
        }

        It 'reports alias-not-declared and keeps the alias in the target id' {
            $ref = @(Get-AzDoPipelineReference -Content "steps:`n  - template: steps/notify.yml@ghostTemplates`n")[0]
            $result = Resolve-AzDoPipelineReference -Reference $ref `
                -SourceRepository 'consumer-app' -SourcePath 'azure-pipelines.yml'

            $result.Resolved | Should-BeFalse
            $result.Reason | Should-BeString 'alias-not-declared'
            $result.TargetId | Should-BeString 'yaml:@ghostTemplates/steps/notify.yml'
        }
    }

    Context 'unresolved references are results, not dropped edges' {

        It 'reports file-not-found when the alias resolved but no such file exists' {
            $ref = @(Get-AzDoPipelineReference -Content "steps:`n  - template: templates/gone.yml`n")[0]
            $result = Resolve-AzDoPipelineReference -Reference $ref `
                -SourceRepository 'pipelines-main' -SourcePath 'p.yml' `
                -TestFile { param($r, $p) $false }

            $result.Resolved | Should-BeFalse
            $result.Reason | Should-BeString 'file-not-found'
        }

        It 'keeps file-not-found and alias-not-declared distinct, because the fixes differ' {
            $missing = @(Get-AzDoPipelineReference -Content "steps:`n  - template: a.yml`n")[0]
            $ghost = @(Get-AzDoPipelineReference -Content "steps:`n  - template: a.yml@nope`n")[0]

            $one = Resolve-AzDoPipelineReference -Reference $missing -SourceRepository 'r' -SourcePath 'p.yml' -TestFile { param($r, $p) $false }
            $two = Resolve-AzDoPipelineReference -Reference $ghost -SourceRepository 'r' -SourcePath 'p.yml'

            $one.Reason | Should-NotBe $two.Reason
        }

        It 'reports repository-not-found when the aliased repository is not in the project' {
            $ref = @(Get-AzDoPipelineReference -Content "steps:`n  - template: a.yml@far`n")[0]
            $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository 'r' -SourcePath 'p.yml' `
                -Alias @{ far = 'elsewhere' } -KnownRepository @('r', 'other')
            $result.Reason | Should-BeString 'repository-not-found'
        }
    }

    Context 'the other three reference kinds' {

        It 'resolves a repositoryResource to a repository node' {
            $ref = @(Get-AzDoPipelineReference -Content @"
resources:
  repositories:
    - repository: mainPipelines
      type: git
      name: pipelines-main
"@)[0]
            $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository 'consumer-app' -SourcePath 'azure-pipelines.yml'
            $result.Resolved | Should-BeTrue
            $result.TargetId | Should-BeString 'repo:pipelines-main'
        }

        It 'strips a project qualifier from a repositoryResource name' {
            $ref = @(Get-AzDoPipelineReference -Content @"
resources:
  repositories:
    - repository: x
      type: git
      name: OtherProject/pipelines-main
"@)[0]
            $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository 'a' -SourcePath 'b.yml'
            $result.TargetId | Should-BeString 'repo:pipelines-main'
        }

        It 'resolves checkout of a declared alias to that repository' {
            $ref = @(Get-AzDoPipelineReference -Content "steps:`n  - checkout: tools`n")[0]
            $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository 'a' -SourcePath 'b.yml' `
                -Alias @{ tools = 'tooling' }
            $result.Resolved | Should-BeTrue
            $result.TargetId | Should-BeString 'repo:tooling'
        }

        It 'reports alias-not-declared for a checkout of an undeclared alias' {
            $ref = @(Get-AzDoPipelineReference -Content "steps:`n  - checkout: tools`n")[0]
            $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository 'a' -SourcePath 'b.yml'
            $result.Reason | Should-BeString 'alias-not-declared'
            $result.TargetId | Should-BeString 'repo:@tools'
        }

        It 'resolves a pipelineResource to a definition node, not to a file' {
            $ref = @(Get-AzDoPipelineReference -Content @"
resources:
  pipelines:
    - pipeline: upstream
      source: Upstream-Build
"@)[0]
            $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository 'a' -SourcePath 'b.yml' `
                -KnownPipeline @('Upstream-Build')
            $result.Resolved | Should-BeTrue
            $result.TargetKind | Should-BeString 'pipeline'
            $result.TargetId | Should-BeString 'pipeline:Upstream-Build'
        }

        It 'reports pipeline-not-found when the named definition is not in the project' {
            $ref = @(Get-AzDoPipelineReference -Content @"
resources:
  pipelines:
    - pipeline: upstream
      source: Nowhere
"@)[0]
            $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository 'a' -SourcePath 'b.yml' `
                -KnownPipeline @('Upstream-Build')
            $result.Reason | Should-BeString 'pipeline-not-found'
        }
    }
}
