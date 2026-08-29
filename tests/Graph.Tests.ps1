#Requires -Version 7.2
<#
    The graph builder against a miniature fixture, with the network mocked. The
    shapes here mirror the real cases: an orphan, a cycle, both unresolved
    reasons, a cross-repository reference, and a repository that exists in the
    project but that no pipeline references.
#>

BeforeAll {
    Import-Module "$PSScriptRoot/../output/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psd1" -Force
}

Describe 'Get-AzDoPipelineDependencyGraph' {

    BeforeAll {
        $script:Yaml = @{
            'main/p-orphan.yml' = "steps:`n  - script: echo standalone`n"
            'main/p-cyc.yml'    = "steps:`n  - template: t/a.yml`n"
            'main/t/a.yml'      = "steps:`n  - template: b.yml`n"
            'main/t/b.yml'      = "steps:`n  - template: a.yml`n"
            'main/p-miss.yml'   = "steps:`n  - template: t/nope.yml`n  - template: s/one.yml@ghost`n"
            'main/p-cross.yml'  = @'
resources:
  repositories:
    - repository: sharedT
      type: git
      name: Proj/shared
steps:
  - checkout: self
  - checkout: sharedT
  - template: s/one.yml@sharedT
'@
            'shared/s/one.yml'  = "steps:`n  - template: two.yml`n"
            'shared/s/two.yml'  = "steps:`n  - script: echo two`n"
        }

        $script:Graph = InModuleScope PSAzureDevOpsGraph -Parameters @{ Yaml = $script:Yaml } {
            param($Yaml)

            Mock Get-AzDoRepository {
                # 'extra' exists in the project and is referenced by nothing.
                @(
                    [pscustomobject]@{ Name = 'main'; Id = 'r1' }
                    [pscustomobject]@{ Name = 'shared'; Id = 'r2' }
                    [pscustomobject]@{ Name = 'extra'; Id = 'r3' }
                )
            }

            Mock Get-AzDoPipeline {
                @(
                    [pscustomobject]@{ Name = 'orphan'; RepositoryName = 'main'; Path = 'p-orphan.yml' }
                    [pscustomobject]@{ Name = 'cyc'; RepositoryName = 'main'; Path = 'p-cyc.yml' }
                    [pscustomobject]@{ Name = 'miss'; RepositoryName = 'main'; Path = 'p-miss.yml' }
                    [pscustomobject]@{ Name = 'cross'; RepositoryName = 'main'; Path = 'p-cross.yml' }
                )
            }

            Mock Get-AzDoPipelineYaml {
                $name = switch ($RepositoryId) { 'r1' { 'main' } 'r2' { 'shared' } default { $RepositoryId } }
                $key = "$name/$Path"
                if ($Yaml.ContainsKey($key)) { $Yaml[$key] } else { $null }
            }

            Get-AzDoPipelineDependencyGraph -Organisation 'org' -Project 'Proj'
        }
    }

    It 'keeps an orphan pipeline as a node' {
        # Building the node set from the edge list makes an orphan cease to
        # exist, and its absence looks exactly like a correct answer.
        @($Graph.nodes | Where-Object id -EQ 'pipeline:orphan').Count | Should-Be 1
        @($Graph.nodes | Where-Object id -EQ 'yaml:main/p-orphan.yml').Count | Should-Be 1
    }

    It 'joins every pipeline to its YAML with one definition edge' {
        @($Graph.edges | Where-Object kind -EQ 'definition').Count | Should-Be 4
    }

    It 'records both edges of a cycle and still terminates' {
        @($Graph.edges | Where-Object { $_.from -eq 'yaml:main/t/a.yml' -and $_.to -eq 'yaml:main/t/b.yml' }).Count |
            Should-Be 1
        @($Graph.edges | Where-Object { $_.from -eq 'yaml:main/t/b.yml' -and $_.to -eq 'yaml:main/t/a.yml' }).Count |
            Should-Be 1
    }

    It 'reports a missing file as unresolved with reason file-not-found' {
        # The reason states the code AND why, because the two unresolved kinds
        # need different fixes and 'not found' tells the reader nothing about
        # which.
        $edge = @($Graph.edges | Where-Object { $_.kind -eq 'unresolved' -and $_.reason -like 'file-not-found*' })
        $edge.Count | Should-Be 1
        $edge[0].ref | Should-Be 't/nope.yml'
        $edge[0].reason | Should-MatchString 'which does not exist'
    }

    It 'reports an undeclared alias as unresolved with reason alias-not-declared' {
        $edge = @($Graph.edges | Where-Object { $_.kind -eq 'unresolved' -and $_.reason -like 'alias-not-declared*' })
        $edge.Count | Should-Be 1
        $edge[0].to | Should-Be 'yaml:@ghost/s/one.yml'
        $edge[0].reason | Should-MatchString 'resources.repositories'
    }

    It 'does not let an unresolved target collide with a real node' {
        $ids = @($Graph.nodes.id)
        $ids | Should-NotContainCollection 'yaml:@ghost/s/one.yml'
    }

    It 'resolves a cross-repository reference from the aliased repository root' {
        @($Graph.edges | Where-Object {
                $_.from -eq 'yaml:main/p-cross.yml' -and $_.to -eq 'yaml:shared/s/one.yml'
            }).Count | Should-Be 1
    }

    It 'keeps a relative reference inside the template''s own repository' {
        @($Graph.edges | Where-Object {
                $_.from -eq 'yaml:shared/s/one.yml' -and $_.to -eq 'yaml:shared/s/two.yml'
            }).Count | Should-Be 1
    }

    It 'makes checkout of an alias a repository edge, not a template edge' {
        $checkout = @($Graph.edges | Where-Object kind -EQ 'checkout')
        $checkout.Count | Should-Be 1
        $checkout[0].to | Should-Be 'repo:shared'
    }

    It 'excludes a repository that no pipeline references' {
        # The obvious first implementation calls the repositories endpoint and
        # turns the result into nodes. 'extra' is returned by that endpoint.
        $ids = @($Graph.nodes.id)
        $ids | Should-NotContainCollection 'repo:extra'
        @($Graph.nodes | Where-Object kind -EQ 'repo').Count | Should-Be 2
    }

    It 'gives every yaml node a repo and a repos-rooted path' {
        foreach ($node in @($Graph.nodes | Where-Object kind -EQ 'yaml')) {
            $node.repo | Should-NotBeNull
            $node.path | Should-BeLikeString 'repos/*'
        }
    }
}
