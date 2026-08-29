#Requires -Version 7.2

BeforeAll {
    Import-Module "$PSScriptRoot/../output/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psd1" -Force
}

Describe 'Get-AzDoPipelineReference' {

    It 'finds a same-repo template reference' {
        $yaml = @'
steps:
  - template: templates/steps-build.yml
'@
        $refs = @(Get-AzDoPipelineReference -Yaml $yaml)
        $refs.Count | Should-Be 1
        $refs[0].RefKind | Should-Be 'template'
        $refs[0].Ref | Should-Be 'templates/steps-build.yml'
        $refs[0].Alias | Should-BeNull
    }

    It 'reports extends.template as an extends reference, not a template one' {
        $yaml = @'
extends:
  template: jobs/release.yml@platformTemplates
'@
        $refs = @(Get-AzDoPipelineReference -Yaml $yaml)
        $refs.Count | Should-Be 1
        $refs[0].RefKind | Should-Be 'extends'
        $refs[0].Alias | Should-Be 'platformTemplates'
        $refs[0].Path | Should-Be 'jobs/release.yml'
    }

    It 'does not invent a reference from a parameter named buildTemplate' {
        # The value is a real, existing path on purpose: a text scanner produces
        # an edge here that resolves, and therefore looks correct.
        $yaml = @'
extends:
  template: jobs/release.yml@platformTemplates
  parameters:
    buildTemplate: templates/steps-build.yml
    environment: staging
'@
        $refs = @(Get-AzDoPipelineReference -Yaml $yaml)
        $refs.Count | Should-Be 1
        $refs[0].Ref | Should-Be 'jobs/release.yml@platformTemplates'
    }

    It 'finds a template under variables, not only under steps' {
        $yaml = @'
variables:
  - template: templates/vars-common.yml
  - name: buildConfiguration
    value: Release
steps:
  - script: echo hi
'@
        $refs = @(Get-AzDoPipelineReference -Yaml $yaml)
        $refs.Count | Should-Be 1
        $refs[0].RefKind | Should-Be 'template'
        $refs[0].Ref | Should-Be 'templates/vars-common.yml'
    }

    It 'reads repository and pipeline resources' {
        $yaml = @'
resources:
  repositories:
    - repository: sharedTemplates
      type: git
      name: ClaudeTesting/templates-shared
  pipelines:
    - pipeline: upstreamBuild
      source: p01-simple-include
      trigger: true
'@
        $refs = @(Get-AzDoPipelineReference -Yaml $yaml)
        $repo = @($refs | Where-Object RefKind -EQ 'repositoryResource')
        $repo.Count | Should-Be 1
        $repo[0].Alias | Should-Be 'sharedTemplates'
        $repo[0].Target | Should-Be 'templates-shared'

        $pipe = @($refs | Where-Object RefKind -EQ 'pipelineResource')
        $pipe.Count | Should-Be 1
        $pipe[0].Target | Should-Be 'p01-simple-include'
    }

    It 'ignores checkout: self and keeps checkout of an alias' {
        $yaml = @'
resources:
  repositories:
    - repository: sharedTemplates
      type: git
      name: ClaudeTesting/templates-shared
steps:
  - checkout: self
  - checkout: sharedTemplates
'@
        $refs = @(Get-AzDoPipelineReference -Yaml $yaml)
        $checkouts = @($refs | Where-Object RefKind -EQ 'checkout')
        $checkouts.Count | Should-Be 1
        $checkouts[0].Ref | Should-Be 'sharedTemplates'
    }

    It 'returns nothing for a pipeline that references nothing' {
        $yaml = @'
steps:
  - script: echo standalone
'@
        @(Get-AzDoPipelineReference -Yaml $yaml).Count | Should-Be 0
    }

    It 'returns nothing for empty text' {
        @(Get-AzDoPipelineReference -Yaml '').Count | Should-Be 0
    }
}

Describe 'Resolve-AzDoPipelineReference' {

    BeforeAll {
        function New-Reference {
            param($Ref, $Kind = 'template')
            $parts = $Ref -split '@', 2
            [pscustomobject]@{
                RefKind = $Kind
                Ref     = $Ref
                Path    = $parts[0]
                Alias   = $(if ($parts.Count -gt 1) { $parts[1] } else { $null })
                Target  = $null
            }
        }
    }

    It 'resolves a same-repo reference relative to the including file' {
        # NOT relative to the repository root. pipelines-main holds both
        # templates/steps-build.yml and pipelines/templates/steps-build.yml, so
        # a root-relative resolver returns the wrong file without erroring.
        $result = Resolve-AzDoPipelineReference -Reference (New-Reference 'templates/steps-build.yml') `
            -FromRepository 'pipelines-main' -FromPath 'pipelines/p01.yml'
        $result.Resolved | Should-BeTrue
        $result.Repository | Should-Be 'pipelines-main'
        $result.Path | Should-Be 'pipelines/templates/steps-build.yml'
    }

    It 'resolves an @alias reference from the root of the aliased repository' {
        $result = Resolve-AzDoPipelineReference -Reference (New-Reference 'templates/steps-build.yml@mainPipelines') `
            -FromRepository 'consumer-app' -FromPath 'azure-pipelines.yml' `
            -Alias @{ mainPipelines = 'pipelines-main' }
        $result.Resolved | Should-BeTrue
        $result.Repository | Should-Be 'pipelines-main'
        $result.Path | Should-Be 'templates/steps-build.yml'
    }

    It 'keeps a relative reference inside the template''s own repository' {
        # The current repository is a property of the file, not of the traversal.
        $result = Resolve-AzDoPipelineReference -Reference (New-Reference 'notify.yml') `
            -FromRepository 'templates-shared' -FromPath 'steps/common.yml'
        $result.Repository | Should-Be 'templates-shared'
        $result.Path | Should-Be 'steps/notify.yml'
    }

    It 'collapses .. segments' {
        $result = Resolve-AzDoPipelineReference -Reference (New-Reference '../steps/deploy.yml') `
            -FromRepository 'templates-platform' -FromPath 'pipelines/trigger.yml'
        $result.Path | Should-Be 'steps/deploy.yml'
    }

    It 'reports alias-not-declared when the alias has no resources entry' {
        $result = Resolve-AzDoPipelineReference -Reference (New-Reference 'steps/common.yml@ghostTemplates') `
            -FromRepository 'pipelines-main' -FromPath 'pipelines/p09.yml' `
            -Alias @{ sharedTemplates = 'templates-shared' }
        $result.Resolved | Should-BeFalse
        $result.Reason | Should-Be 'alias-not-declared'
    }

    It 'passes non-template references through as resolved' {
        $result = Resolve-AzDoPipelineReference -Reference (New-Reference 'sharedTemplates' 'checkout') `
            -FromRepository 'consumer-app' -FromPath 'azure-pipelines.yml'
        $result.Resolved | Should-BeTrue
    }
}
