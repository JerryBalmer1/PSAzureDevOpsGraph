#Requires -Version 7.2

BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    $script:Module = Import-ModuleUnderTest
}

Describe 'Get-AzDoPipelineReference' {

    It 'finds a template reference under steps' {
        $result = @(Get-AzDoPipelineReference -Yaml 'steps: [ { template: templates/steps-build.yml } ]')
        $result.Count | Should-Be 1
        $result[0].RefKind | Should-Be 'template'
        $result[0].Ref | Should-Be 'templates/steps-build.yml'
    }

    It 'finds a template under variables, because the whole document is walked' {
        # Hard-coding steps/jobs/stages covers most real references and silently
        # loses this one.
        $yaml = "variables:`n  - template: templates/vars-common.yml`n"
        $result = @(Get-AzDoPipelineReference -Yaml $yaml)
        $result.Count | Should-Be 1
        $result[0].RefKind | Should-Be 'template'
    }

    It 'does not invent an edge from buildTemplate, which is not template' {
        # The parameter's default is a real, existing path precisely so that a
        # substring match produces an edge that resolves and looks correct.
        $yaml = "parameters:`n  - name: buildTemplate`n    default: templates/steps-build.yml`n"
        @(Get-AzDoPipelineReference -Yaml $yaml).Count | Should-Be 0
    }

    It 'gives extends.template the kind extends, not template' {
        $yaml = "extends:`n  template: templates/base.yml`n"
        $result = @(Get-AzDoPipelineReference -Yaml $yaml)
        $result[0].RefKind | Should-Be 'extends'
    }

    It 'treats a template nested under extends.parameters as an ordinary template' {
        $yaml = "extends:`n  template: base.yml`n  parameters:`n    inner:`n      - template: jobs/nested.yml`n"
        $result = @(Get-AzDoPipelineReference -Yaml $yaml)
        @($result | Where-Object RefKind -eq 'extends').Count | Should-Be 1
        @($result | Where-Object RefKind -eq 'template').Count | Should-Be 1
    }

    It 'splits path@alias into its two halves and keeps the raw text' {
        $result = @(Get-AzDoPipelineReference -Yaml 'steps: [ { template: "templates/x.yml@shared" } ]')
        $result[0].Ref | Should-Be 'templates/x.yml@shared'
        $result[0].Path | Should-Be 'templates/x.yml'
        $result[0].Alias | Should-Be 'shared'
    }

    It 'yields nothing at all for checkout self and checkout none' {
        $yaml = "steps:`n  - checkout: self`n  - checkout: none`n"
        @(Get-AzDoPipelineReference -Yaml $yaml).Count | Should-Be 0
    }

    It 'makes checkout of an alias a checkout reference and never a template one' {
        $yaml = "steps:`n  - checkout: sharedTemplates`n"
        $result = @(Get-AzDoPipelineReference -Yaml $yaml)
        $result.Count | Should-Be 1
        $result[0].RefKind | Should-Be 'checkout'
    }

    It 'reads resources.repositories as a repository reference carrying its alias' {
        $yaml = "resources:`n  repositories:`n    - repository: mainPipelines`n      type: git`n      name: Proj/pipelines-main`n"
        $result = @(Get-AzDoPipelineReference -Yaml $yaml)
        $result[0].RefKind | Should-Be 'repositoryResource'
        $result[0].Alias | Should-Be 'mainPipelines'
        $result[0].Target | Should-Be 'pipelines-main'
    }

    It 'reads resources.pipelines as pointing at a definition, not a file' {
        $yaml = "resources:`n  pipelines:`n    - pipeline: upstream`n      source: p01-build`n"
        $result = @(Get-AzDoPipelineReference -Yaml $yaml)
        $result[0].RefKind | Should-Be 'pipelineResource'
        $result[0].Target | Should-Be 'p01-build'
    }

    It 'returns nothing for a document that does not parse' {
        @(Get-AzDoPipelineReference -Yaml "steps:`n  - a`n   - b: [unclosed`n").Count | Should-Be 0
    }

    It 'parses a file on disk with no credential and no network' {
        $file = Join-Path $TestDrive 'p.yml'
        Set-Content -LiteralPath $file -Value 'steps: [ { template: t.yml } ]'
        @(Get-AzDoPipelineReference -Path $file).Count | Should-Be 1
    }

    It 'throws when the file is not there' {
        { Get-AzDoPipelineReference -Path (Join-Path $TestDrive 'absent.yml') } | Should-Throw
    }
}
