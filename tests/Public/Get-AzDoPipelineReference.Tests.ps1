#Requires -Version 7.2
BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    Import-BuiltModule
    $script:Consumer = Get-Content -LiteralPath (Get-YamlFixturePath 'consumer.yml') -Raw
    $script:References = @(Get-AzDoPipelineReference -Content $script:Consumer)
}

Describe 'Get-AzDoPipelineReference' {

    It 'parses a document with no credentials and no network' {
        $script:References.Count | Should-BeGreaterThan 0
    }

    It 'gives extends.template the kind extends, not template' {
        $extends = @($script:References | Where-Object { $_.Kind -eq 'extends' })
        $extends.Count | Should-Be 1
        $extends[0].Reference | Should-BeString 'templates/stages-standard.yml@mainPipelines'
        $extends[0].Alias | Should-BeString 'mainPipelines'
        $extends[0].Path | Should-BeString 'templates/stages-standard.yml'
    }

    It 'finds a template under variables, which is not a steps/jobs/stages block' {
        $refs = @($script:References | Where-Object { $_.Reference -eq 'templates/vars-common.yml' })
        $refs.Count | Should-Be 1
        $refs[0].Kind | Should-BeString 'template'
    }

    It 'does not invent a reference from buildTemplate, which only contains the word' {
        # The parameter default is a real, existing-looking path precisely so a
        # substring scan produces an edge that resolves and therefore looks
        # correct.
        $refs = @($script:References | Where-Object { $_.Reference -eq 'templates/steps-build.yml' })
        $refs.Count | Should-Be 0
    }

    It 'records the raw reference text and the alias separately' {
        $ghost = @($script:References | Where-Object { $_.Alias -eq 'ghostTemplates' })
        $ghost.Count | Should-Be 1
        $ghost[0].Reference | Should-BeString 'steps/notify.yml@ghostTemplates'
        $ghost[0].Path | Should-BeString 'steps/notify.yml'
    }

    It 'reads resources.repositories as repositoryResource with its alias' {
        $repos = @($script:References | Where-Object { $_.Kind -eq 'repositoryResource' })
        $repos.Count | Should-Be 2
        ($repos | Where-Object Alias -eq 'mainPipelines').Name | Should-BeString 'pipelines-main'
        ($repos | Where-Object Alias -eq 'tools').Name | Should-BeString 'tooling'
    }

    It 'reads resources.pipelines as a reference to a definition, not to a file' {
        $pipelines = @($script:References | Where-Object { $_.Kind -eq 'pipelineResource' })
        $pipelines.Count | Should-Be 1
        $pipelines[0].Name | Should-BeString 'Upstream-Build'
        $pipelines[0].Alias | Should-BeString 'upstream'
    }

    It 'yields a checkout reference for another repository but nothing for self' {
        $checkouts = @($script:References | Where-Object { $_.Kind -eq 'checkout' })
        $checkouts.Count | Should-Be 1
        $checkouts[0].Reference | Should-BeString 'tools'
    }

    It 'yields nothing at all for a document of self, none and a lookalike script line' {
        $refs = @(Get-AzDoPipelineReference -Content (Get-Content -LiteralPath (Get-YamlFixturePath 'selfonly.yml') -Raw))
        $refs.Count | Should-Be 0
    }

    It 'reads a file on disk with no credentials' {
        $refs = @(Get-AzDoPipelineReference -Path (Get-YamlFixturePath 'consumer.yml'))
        $refs.Count | Should-Be $script:References.Count
    }

    It 'throws naming the path when the file is not there' {
        { Get-AzDoPipelineReference -Path "$PSScriptRoot/no-such-file.yml" } | Should-Throw -ExceptionMessage '*no-such-file.yml*'
    }

    It 'treats a document that will not parse as a result, not a crash' {
        $refs = @(Get-AzDoPipelineReference -Content (Get-Content -LiteralPath (Get-YamlFixturePath 'malformed.yml') -Raw))
        $refs.Count | Should-Be 0
    }

    It 'returns nothing for empty content rather than throwing' {
        @(Get-AzDoPipelineReference -Content '').Count | Should-Be 0
    }

    It 'accepts the Content property from a yaml record on the pipeline' {
        $record = [pscustomobject]@{ PSTypeName = 'PSAzureDevOpsGraph.Yaml'; Content = $script:Consumer }
        @($record | Get-AzDoPipelineReference).Count | Should-Be $script:References.Count
    }
}
