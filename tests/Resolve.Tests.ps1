#requires -Modules Pester

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'src' 'PSAzureDevOpsGraph' 'PSAzureDevOpsGraph.psd1') -Force

    $script:Repos = @(
        [pscustomobject]@{ Name = 'pipelines-main';     IsEmpty = $false }
        [pscustomobject]@{ Name = 'templates-shared';   IsEmpty = $false }
        [pscustomobject]@{ Name = 'templates-platform'; IsEmpty = $false }
    )

    $script:Inventory = @{}
    $script:Inventory['pipelines-main'] = [System.Collections.Generic.HashSet[string]]@(
        'pipelines/p01.yml'
        'pipelines/templates/steps-build.yml'
        'templates/steps-build.yml'
    )
    $script:Inventory['templates-shared'] = [System.Collections.Generic.HashSet[string]]@(
        'steps/common.yml'
    )
    $script:Inventory['templates-platform'] = [System.Collections.Generic.HashSet[string]]@()

    $script:Aliases = @{
        shared = @{ Repository = 'templates-shared'; Project = 'ClaudeTesting'; Type = 'git'; Ref = $null }
        hub    = @{ Repository = 'no-such-repo';     Project = 'ClaudeTesting'; Type = 'git'; Ref = $null }
        gh     = @{ Repository = 'something';        Project = '';              Type = 'github'; Ref = $null }
    }

    function script:Resolve1 {
        param($Kind, $Reference, $SourcePath = 'pipelines/p01.yml', $SourceRepository = 'pipelines-main')
        $ref = Get-AzDoPipelineReference -Content "steps:`n  - template: placeholder" | Select-Object -First 1
        $ref = [pscustomobject]@{
            Kind = $Kind; Reference = $Reference; Alias = $null
            RepositoryName = $Reference; ResourceType = 'git'; Source = $Reference
        }
        Resolve-AzDoPipelineReference -Reference $ref -SourceRepository $SourceRepository `
            -SourcePath $SourcePath -AliasMap $script:Aliases -Repository $script:Repos `
            -Inventory $script:Inventory -Project 'ClaudeTesting'
    }
}

Describe 'Resolve-AzDoPipelineReference' {

    Context 'the two anchoring rules' {

        It 'resolves an un-aliased path relative to the referring file directory' {
            $r = script:Resolve1 -Kind 'template' -Reference 'templates/steps-build.yml' `
                                 -SourcePath 'pipelines/p01.yml'
            $r.Resolved         | Should -BeTrue
            $r.TargetRepository | Should -Be 'pipelines-main'
            $r.TargetPath       | Should -Be 'pipelines/templates/steps-build.yml'
        }

        It 'resolves an aliased path from the root of the aliased repository' {
            $r = script:Resolve1 -Kind 'template' -Reference 'steps/common.yml@shared' `
                                 -SourcePath 'pipelines/p01.yml'
            $r.Resolved         | Should -BeTrue
            $r.TargetRepository | Should -Be 'templates-shared'
            $r.TargetPath       | Should -Be 'steps/common.yml'
        }

        It 'sends the same relative text to different files depending on the alias' {
            # This is the pair the fixture exists to separate: 'templates/
            # steps-build.yml' means one file bare and a different file aliased.
            $bare    = script:Resolve1 -Kind 'template' -Reference 'templates/steps-build.yml'
            $aliased = script:Resolve1 -Kind 'template' -Reference 'templates/steps-build.yml@self'

            $bare.TargetPath    | Should -Be 'pipelines/templates/steps-build.yml'
            $aliased.TargetPath | Should -Be 'templates/steps-build.yml'
            $bare.TargetPath    | Should -Not -Be $aliased.TargetPath
        }

        It 'anchors a leading slash at the repository root even without an alias' {
            $r = script:Resolve1 -Kind 'template' -Reference '/templates/steps-build.yml'
            $r.TargetPath | Should -Be 'templates/steps-build.yml'
        }

        It 'walks up through ..' {
            $r = script:Resolve1 -Kind 'template' -Reference '../templates/steps-build.yml' `
                                 -SourcePath 'pipelines/p01.yml'
            $r.TargetPath | Should -Be 'templates/steps-build.yml'
        }
    }

    Context 'failures are results, not exceptions' {

        It 'reports an undeclared alias with a reason' {
            $r = script:Resolve1 -Kind 'template' -Reference 'steps/common.yml@ghost'
            $r.Resolved | Should -BeFalse
            $r.Reason   | Should -Match "alias 'ghost' is not declared"
        }

        It 'reports a missing file with a reason' {
            $r = script:Resolve1 -Kind 'template' -Reference 'templates/absent.yml'
            $r.Resolved | Should -BeFalse
            $r.Reason   | Should -Match 'does not exist'
        }

        It 'reports an alias pointing at a repository that is not there' {
            $r = script:Resolve1 -Kind 'template' -Reference 'steps/common.yml@hub'
            $r.Resolved | Should -BeFalse
            $r.Reason   | Should -Match 'does not exist in project'
        }

        It 'declines a non-git repository resource' {
            $r = script:Resolve1 -Kind 'template' -Reference 'steps/common.yml@gh'
            $r.Resolved | Should -BeFalse
            $r.Reason   | Should -Match "type 'github'"
        }

        It 'never throws on a broken reference' {
            { script:Resolve1 -Kind 'template' -Reference 'x/y/z.yml@nope' } | Should -Not -Throw
        }
    }

    Context 'checkout' {

        It 'resolves self to the referring repository' {
            $r = script:Resolve1 -Kind 'checkout' -Reference 'self'
            $r.Resolved         | Should -BeTrue
            $r.TargetKind       | Should -Be 'repo'
            $r.TargetRepository | Should -Be 'pipelines-main'
        }

        It 'treats none as a directive rather than a dependency' {
            $r = script:Resolve1 -Kind 'checkout' -Reference 'none'
            $r.Resolved   | Should -BeTrue
            $r.TargetKind | Should -Be 'none'
        }

        It 'resolves an alias to its repository' {
            $r = script:Resolve1 -Kind 'checkout' -Reference 'shared'
            $r.TargetRepository | Should -Be 'templates-shared'
        }
    }
}

Describe 'Repository path arithmetic' {

    BeforeAll {
        $script:Module = Get-Module PSAzureDevOpsGraph
    }

    It 'normalises <ref> from <base> to <expected>' -ForEach @(
        @{ base = 'pipelines';      ref = 'templates/a.yml';    expected = 'pipelines/templates/a.yml' }
        @{ base = 'pipelines';      ref = './a.yml';            expected = 'pipelines/a.yml' }
        @{ base = 'pipelines';      ref = '../a.yml';           expected = 'a.yml' }
        @{ base = 'a/b/c';          ref = '../../d.yml';        expected = 'a/d.yml' }
        @{ base = 'pipelines';      ref = '/root.yml';          expected = 'root.yml' }
        @{ base = '';               ref = 'a.yml';              expected = 'a.yml' }
    ) {
        & $script:Module { param($b, $r) Join-AzDoRepositoryPath -BaseDirectory $b -ReferencePath $r } $base $ref |
            Should -Be $expected
    }
}
