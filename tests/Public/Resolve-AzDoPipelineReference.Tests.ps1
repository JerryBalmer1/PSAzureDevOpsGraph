BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    Import-ModuleUnderTest | Out-Null

    $script:MakeReference = {
        param($Kind, $Reference, $Path, $Alias, $Repository)
        [pscustomobject] @{
            PSTypeName = 'PSAzureDevOpsGraph.Reference'
            Kind       = $Kind
            Reference  = $Reference
            Path       = $Path
            Alias      = $Alias
            Repository = $Repository
        }
    }
}

Describe 'Resolve-AzDoPipelineReference' {

    It 'resolves a reference with no alias relative to the directory of the file, not the repository root' {
        # pipelines-main holds BOTH templates/steps-build.yml and
        # pipelines/templates/steps-build.yml. A root-relative resolver does not
        # error here - it returns the wrong file, confidently.
        $reference = & $script:MakeReference 'template' 'templates/steps-build.yml' 'templates/steps-build.yml' $null $null
        $resolution = Resolve-AzDoPipelineReference -Reference $reference `
            -SourceRepository 'pipelines-main' -SourcePath 'pipelines/p01.yml'

        $resolution.Resolved | Should-BeTrue
        $resolution.Repository | Should-Be 'pipelines-main'
        $resolution.Path | Should-Be 'pipelines/templates/steps-build.yml'
        $resolution.TargetId | Should-Be 'yaml:pipelines-main/pipelines/templates/steps-build.yml'
    }

    It 'resolves an @alias reference from the root of the aliased repository' {
        $reference = & $script:MakeReference 'template' 'templates/steps-build.yml@mainPipelines' 'templates/steps-build.yml' 'mainPipelines' $null
        $resolution = Resolve-AzDoPipelineReference -Reference $reference `
            -SourceRepository 'consumer-app' -SourcePath 'azure-pipelines.yml' `
            -Alias @{ mainPipelines = 'pipelines-main' }

        $resolution.Resolved | Should-BeTrue
        $resolution.Repository | Should-Be 'pipelines-main'
        $resolution.Path | Should-Be 'templates/steps-build.yml'
    }

    It 'keeps the current repository a property of the file rather than of the traversal' {
        # A relative reference inside a cross-repo template stays in THAT
        # template's repository.
        $reference = & $script:MakeReference 'template' 'notify.yml' 'notify.yml' $null $null
        $resolution = Resolve-AzDoPipelineReference -Reference $reference `
            -SourceRepository 'templates-shared' -SourcePath 'steps/common.yml'

        $resolution.Repository | Should-Be 'templates-shared'
        $resolution.Path | Should-Be 'steps/notify.yml'
    }

    It 'reports alias-not-declared, with the alias kept in the target id' {
        $reference = & $script:MakeReference 'template' 'steps/common.yml@ghostTemplates' 'steps/common.yml' 'ghostTemplates' $null
        $resolution = Resolve-AzDoPipelineReference -Reference $reference `
            -SourceRepository 'consumer-app' -SourcePath 'azure-pipelines.yml' -Alias @{}

        $resolution.Resolved | Should-BeFalse
        $resolution.Reason | Should-Be 'alias-not-declared'
        $resolution.TargetId | Should-Be 'yaml:@ghostTemplates/steps/common.yml'
    }

    It 'reports file-not-found when the alias resolved but no such file exists' {
        $reference = & $script:MakeReference 'template' 'templates/gone.yml' 'templates/gone.yml' $null $null
        $resolution = Resolve-AzDoPipelineReference -Reference $reference `
            -SourceRepository 'pipelines-main' -SourcePath 'p.yml' `
            -TestFile { param($r, $p) $false }

        $resolution.Resolved | Should-BeFalse
        $resolution.Reason | Should-Be 'file-not-found'
    }

    It 'keeps the two unresolved reasons distinct, because they need different fixes' {
        $missingFile = & $script:MakeReference 'template' 'a.yml' 'a.yml' $null $null
        $missingAlias = & $script:MakeReference 'template' 'a.yml@nope' 'a.yml' 'nope' $null

        $first = Resolve-AzDoPipelineReference -Reference $missingFile -SourceRepository 'r' -SourcePath 'p.yml' -TestFile { param($r, $p) $false }
        $second = Resolve-AzDoPipelineReference -Reference $missingAlias -SourceRepository 'r' -SourcePath 'p.yml'

        $first.Reason | Should-Be 'file-not-found'
        $second.Reason | Should-Be 'alias-not-declared'
    }

    It 'resolves a checkout to the repository its alias names' {
        $reference = & $script:MakeReference 'checkout' 'templatesShared' $null 'templatesShared' $null
        $resolution = Resolve-AzDoPipelineReference -Reference $reference `
            -SourceRepository 'consumer-app' -SourcePath 'azure-pipelines.yml' `
            -Alias @{ templatesShared = 'templates-shared' }

        $resolution.TargetKind | Should-Be 'repo'
        $resolution.TargetId | Should-Be 'repo:templates-shared'
    }

    It 'resolves a pipeline resource to a definition node' {
        $reference = & $script:MakeReference 'pipelineResource' 'Build-Core' $null 'upstream' $null
        $resolution = Resolve-AzDoPipelineReference -Reference $reference -SourceRepository 'r' -SourcePath 'p.yml'

        $resolution.TargetKind | Should-Be 'pipeline'
        $resolution.TargetId | Should-Be 'pipeline:Build-Core'
    }

    It 'normalises a parent-relative reference' {
        $reference = & $script:MakeReference 'template' '../shared/x.yml' '../shared/x.yml' $null $null
        $resolution = Resolve-AzDoPipelineReference -Reference $reference -SourceRepository 'r' -SourcePath 'pipelines/nested/p.yml'
        $resolution.Path | Should-Be 'pipelines/shared/x.yml'
    }
}
