#Requires -Version 7.2

BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    $script:Module = Import-ModuleUnderTest

    $script:Aliases = @{ mainPipelines = 'pipelines-main'; sharedTemplates = 'templates-shared' }

    # A repository holding BOTH templates/steps-build.yml and
    # pipelines/templates/steps-build.yml. This is the pair that tells a
    # directory-relative resolver from a root-relative one: the wrong one does
    # not error, it returns the other file, confidently.
    $script:Known = @(
        'pipelines-main/templates/steps-build.yml'
        'pipelines-main/pipelines/templates/steps-build.yml'
        'templates-shared/steps/common.yml'
    )
}

Describe 'Resolve-AzDoPipelineReference' {

    It 'resolves a bare reference relative to the DIRECTORY of the including file' {
        $ref = Get-AzDoPipelineReference -Yaml 'steps: [ { template: templates/steps-build.yml } ]'
        $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository pipelines-main -SourcePath pipelines/p01.yml -Alias $script:Aliases -KnownPath $script:Known
        $result.Resolved | Should-BeTrue
        $result.Path | Should-Be 'pipelines/templates/steps-build.yml'
    }

    It 'resolves an @alias reference from the ROOT of the aliased repository' {
        $ref = Get-AzDoPipelineReference -Yaml 'steps: [ { template: "templates/steps-build.yml@mainPipelines" } ]'
        $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository consumer-app -SourcePath azure-pipelines.yml -Alias $script:Aliases -KnownPath $script:Known
        $result.Resolved | Should-BeTrue
        $result.Repository | Should-Be 'pipelines-main'
        $result.Path | Should-Be 'templates/steps-build.yml'
    }

    It 'gives the two rules different files from the same reference text' {
        $bare = Get-AzDoPipelineReference -Yaml 'steps: [ { template: templates/steps-build.yml } ]'
        $aliased = Get-AzDoPipelineReference -Yaml 'steps: [ { template: "templates/steps-build.yml@mainPipelines" } ]'
        $a = Resolve-AzDoPipelineReference -Reference $bare -SourceRepository pipelines-main -SourcePath pipelines/p01.yml -Alias $script:Aliases -KnownPath $script:Known
        $b = Resolve-AzDoPipelineReference -Reference $aliased -SourceRepository pipelines-main -SourcePath pipelines/p01.yml -Alias $script:Aliases -KnownPath $script:Known
        $a.Path | Should-NotBe $b.Path
    }

    It 'reports alias-not-declared for an alias this file does not declare' {
        $ref = Get-AzDoPipelineReference -Yaml 'steps: [ { template: "steps/common.yml@ghostTemplates" } ]'
        $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository pipelines-main -SourcePath pipelines/p09.yml -Alias $script:Aliases -KnownPath $script:Known
        $result.Resolved | Should-BeFalse
        $result.Reason | Should-MatchString "^alias-not-declared: 'ghostTemplates' is not in resources.repositories of pipelines/p09.yml"
    }

    It 'reports file-not-found when the alias resolved but no such file exists' {
        # The two reasons are kept apart because the fixes differ: one wants a
        # resources.repositories entry, the other wants the file.
        $ref = Get-AzDoPipelineReference -Yaml 'steps: [ { template: templates/missing-steps.yml } ]'
        $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository pipelines-main -SourcePath pipelines/p09.yml -Alias $script:Aliases -KnownPath $script:Known
        $result.Resolved | Should-BeFalse
        $result.Reason | Should-MatchString '^file-not-found: resolved to pipelines/templates/missing-steps.yml in pipelines-main'
    }

    It 'keeps the current repository a property of the file, not of the traversal' {
        # A relative reference inside a cross-repo template stays in THAT
        # template's repository.
        $ref = Get-AzDoPipelineReference -Yaml 'steps: [ { template: common.yml } ]'
        $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository templates-shared -SourcePath steps/notify.yml -Alias $script:Aliases -KnownPath $script:Known
        $result.Repository | Should-Be 'templates-shared'
        $result.Path | Should-Be 'steps/common.yml'
    }

    It 'resolves .. segments without touching the filesystem' {
        $ref = Get-AzDoPipelineReference -Yaml 'steps: [ { template: ../templates/steps-build.yml } ]'
        $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository pipelines-main -SourcePath pipelines/sub/p.yml -Alias $script:Aliases -KnownPath $script:Known
        $result.Path | Should-Be 'pipelines/templates/steps-build.yml'
    }

    It 'resolves a checkout alias to the repository the file declared' {
        $ref = Get-AzDoPipelineReference -Yaml "steps:`n  - checkout: sharedTemplates`n"
        $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository consumer-app -SourcePath azure-pipelines.yml -Alias $script:Aliases -KnownPath $script:Known
        $result.Resolved | Should-BeTrue
        $result.TargetKind | Should-Be 'repo'
        $result.Repository | Should-Be 'templates-shared'
    }

    It 'reports alias-not-declared for a checkout of an alias this file never declared' {
        $ref = Get-AzDoPipelineReference -Yaml "steps:`n  - checkout: neverDeclared`n"
        $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository consumer-app -SourcePath azure-pipelines.yml -Alias @{} -KnownPath $script:Known
        $result.Resolved | Should-BeFalse
        $result.Reason | Should-MatchString '^alias-not-declared: '
    }

    It 'points a pipeline resource at a definition rather than a file' {
        $ref = Get-AzDoPipelineReference -Yaml "resources:`n  pipelines:`n    - pipeline: upstream`n      source: p01-build`n"
        $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository pipelines-main -SourcePath pipelines/p05.yml -Alias $script:Aliases -KnownPath $script:Known
        $result.TargetKind | Should-Be 'pipeline'
        $result.Name | Should-Be 'p01-build'
    }

    It 'asserts no existence at all when KnownPath is not supplied' {
        # Which is what lets resolution be tested with no credentials.
        $ref = Get-AzDoPipelineReference -Yaml 'steps: [ { template: anything/at/all.yml } ]'
        $result = Resolve-AzDoPipelineReference -Reference $ref -SourceRepository r -SourcePath a/b.yml
        $result.Resolved | Should-BeTrue
    }

    It 'accepts references from the pipeline' {
        $yaml = "steps:`n  - template: templates/steps-build.yml`n  - checkout: sharedTemplates`n"
        $results = @(Get-AzDoPipelineReference -Yaml $yaml |
                Resolve-AzDoPipelineReference -SourceRepository pipelines-main -SourcePath pipelines/p01.yml -Alias $script:Aliases -KnownPath $script:Known)
        $results.Count | Should-Be 2
    }
}
