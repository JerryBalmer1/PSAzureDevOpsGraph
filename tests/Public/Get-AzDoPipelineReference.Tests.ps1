BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    Import-ModuleUnderTest | Out-Null
}

Describe 'Get-AzDoPipelineReference' {

    It 'finds a template reference under variables, not only under steps' {
        $yaml = @'
variables:
  - template: templates/vars-common.yml
steps:
  - script: echo hello
'@
        $references = @(Get-AzDoPipelineReference -Yaml $yaml)
        $references.Count | Should-Be 1
        $references[0].Kind | Should-Be 'template'
        $references[0].Reference | Should-Be 'templates/vars-common.yml'
    }

    It 'does not invent a reference from buildTemplate' {
        # buildTemplate is not template. A substring match on "template:" invents
        # an edge from a parameter, and parameter values are chosen to be real
        # existing paths precisely so that the invented edge resolves.
        $yaml = @'
parameters:
  - name: buildTemplate
    default: templates/steps-build.yml
steps:
  - script: echo hello
'@
        @(Get-AzDoPipelineReference -Yaml $yaml).Count | Should-Be 0
    }

    It 'does not treat a parameter value that looks like a path as a reference' {
        $yaml = @'
parameters:
  templatePath: templates/steps-build.yml
steps:
  - script: echo hello
'@
        @(Get-AzDoPipelineReference -Yaml $yaml).Count | Should-Be 0
    }

    It 'gives extends its own kind rather than collapsing it into template' {
        $yaml = @'
extends:
  template: templates/base.yml@shared
'@
        $references = @(Get-AzDoPipelineReference -Yaml $yaml)
        $references.Count | Should-Be 1
        $references[0].Kind | Should-Be 'extends'
        $references[0].Alias | Should-Be 'shared'
        $references[0].Path | Should-Be 'templates/base.yml'
        $references[0].Reference | Should-Be 'templates/base.yml@shared'
    }

    It 'yields nothing at all for checkout: self' {
        $yaml = @'
steps:
  - checkout: self
'@
        @(Get-AzDoPipelineReference -Yaml $yaml).Count | Should-Be 0
    }

    It 'treats checkout of another repository as a repository dependency, not a template one' {
        $yaml = @'
steps:
  - checkout: templatesShared
'@
        $references = @(Get-AzDoPipelineReference -Yaml $yaml)
        $references.Count | Should-Be 1
        $references[0].Kind | Should-Be 'checkout'
        $references[0].Alias | Should-Be 'templatesShared'
    }

    It 'returns the aliases a file declares alongside the references that use them' {
        $yaml = @'
resources:
  repositories:
    - repository: mainPipelines
      type: git
      name: ClaudeTesting/pipelines-main
steps:
  - template: templates/steps-build.yml@mainPipelines
'@
        $references = @(Get-AzDoPipelineReference -Yaml $yaml)
        $declaration = $references | Where-Object { $_.Kind -eq 'repositoryResource' }
        $declaration.Alias | Should-Be 'mainPipelines'
        $declaration.Repository | Should-Be 'pipelines-main'
        $declaration.Reference | Should-Be 'ClaudeTesting/pipelines-main'

        $use = $references | Where-Object { $_.Kind -eq 'template' }
        $use.Alias | Should-Be 'mainPipelines'
    }

    It 'points a pipeline resource at a definition rather than at a file' {
        $yaml = @'
resources:
  pipelines:
    - pipeline: upstream
      source: Build-Core
'@
        $references = @(Get-AzDoPipelineReference -Yaml $yaml)
        $references.Count | Should-Be 1
        $references[0].Kind | Should-Be 'pipelineResource'
        $references[0].Reference | Should-Be 'Build-Core'
    }

    It 'reads a document from a file as well as from a string' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) "azdo-ref-$([guid]::NewGuid()).yml"
        Set-Content -LiteralPath $path -Value "steps:`n  - template: templates/x.yml" -Encoding utf8NoBOM
        try {
            $references = @(Get-AzDoPipelineReference -Path $path)
            $references[0].Reference | Should-Be 'templates/x.yml'
        } finally {
            Remove-Item -LiteralPath $path -Force
        }
    }

    It 'returns nothing for a document that is not YAML rather than throwing' {
        @(Get-AzDoPipelineReference -Yaml "steps:`n  - a: [1, 2`n   bad indent: {" ).Count | Should-Be 0
    }
}
