#requires -Modules Pester

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'src' 'PSAzureDevOpsGraph' 'PSAzureDevOpsGraph.psd1') -Force
}

Describe 'Get-AzDoPipelineReference' {

    It 'needs no credential and no network' {
        # Parsing must stay testable with nothing configured. If this command
        # ever grows a REST call, this test fails rather than the whole suite
        # quietly requiring a PAT.
        $saved = $env:AZDO_PAT
        try {
            $env:AZDO_PAT = $null
            { Get-AzDoPipelineReference -Content "steps:`n  - template: a.yml" } | Should -Not -Throw
        }
        finally { $env:AZDO_PAT = $saved }
    }

    It 'finds a template reference in steps' {
        $refs = @(Get-AzDoPipelineReference -Content "steps:`n  - template: templates/build.yml")
        $refs.Count            | Should -Be 1
        $refs[0].Kind          | Should -Be 'template'
        $refs[0].Reference     | Should -Be 'templates/build.yml'
        $refs[0].Alias         | Should -BeNullOrEmpty
    }

    It 'splits an alias off a template reference' {
        $refs = @(Get-AzDoPipelineReference -Content "steps:`n  - template: steps/common.yml@shared")
        $refs[0].Alias | Should -Be 'shared'
        $refs[0].Path  | Should -Be 'steps/common.yml'
    }

    It 'reports an extends template as extends, not as template' {
        $yaml = "extends:`n  template: base.yml@platform`n  parameters:`n    env: prod"
        $refs = @(Get-AzDoPipelineReference -Content $yaml)
        @($refs | Where-Object Kind -eq 'extends').Count  | Should -Be 1
        @($refs | Where-Object Kind -eq 'template').Count | Should -Be 0
    }

    It 'still finds templates nested inside extends parameters' {
        $yaml = @'
extends:
  template: base.yml@platform
  parameters:
    steps:
      - template: extra.yml
'@
        $refs = @(Get-AzDoPipelineReference -Content $yaml)
        @($refs | Where-Object Kind -eq 'extends').Count  | Should -Be 1
        @($refs | Where-Object { $_.Kind -eq 'template' -and $_.Reference -eq 'extra.yml' }).Count | Should -Be 1
    }

    It 'reads repository resources as alias declarations' {
        $yaml = @'
resources:
  repositories:
    - repository: shared
      type: git
      name: Proj/templates-shared
      ref: refs/heads/main
'@
        $refs = @(Get-AzDoPipelineReference -Content $yaml | Where-Object Kind -eq 'repositoryResource')
        $refs.Count               | Should -Be 1
        $refs[0].Alias            | Should -Be 'shared'
        $refs[0].RepositoryName   | Should -Be 'Proj/templates-shared'
        $refs[0].ResourceType     | Should -Be 'git'
        $refs[0].RepositoryRef    | Should -Be 'refs/heads/main'
    }

    It 'reads two repository resources in one document' {
        $yaml = @'
resources:
  repositories:
    - repository: one
      type: git
      name: Proj/a
    - repository: two
      type: git
      name: Proj/b
'@
        @(Get-AzDoPipelineReference -Content $yaml | Where-Object Kind -eq 'repositoryResource').Count |
            Should -Be 2
    }

    It 'reads pipeline resources' {
        $yaml = @'
resources:
  pipelines:
    - pipeline: upstream
      source: p01-simple-include
'@
        $refs = @(Get-AzDoPipelineReference -Content $yaml | Where-Object Kind -eq 'pipelineResource')
        $refs.Count       | Should -Be 1
        $refs[0].Alias    | Should -Be 'upstream'
        $refs[0].Source   | Should -Be 'p01-simple-include'
    }

    It 'reads checkout steps' {
        $yaml = "steps:`n  - checkout: self`n  - checkout: shared`n  - checkout: none"
        $refs = @(Get-AzDoPipelineReference -Content $yaml | Where-Object Kind -eq 'checkout')
        $refs.Count | Should -Be 3
        $refs.Reference | Should -Be @('self', 'shared', 'none')
    }

    It 'does not read a template out of a shell script' {
        # The wrong answer this guards: a regex over the raw file reports the
        # echoed line as a real reference and invents an edge.
        $yaml = @'
steps:
  - script: |
      echo "template: phantom.yml@ghost"
  - template: real.yml
'@
        $refs = @(Get-AzDoPipelineReference -Content $yaml | Where-Object Kind -eq 'template')
        $refs.Count        | Should -Be 1
        $refs[0].Reference | Should -Be 'real.yml'
    }

    It 'returns nothing for an empty document' {
        @(Get-AzDoPipelineReference -Content '').Count | Should -Be 0
    }
}
