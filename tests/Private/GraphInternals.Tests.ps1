#Requires -Version 7.2
BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    Import-BuiltModule
}

Describe 'Resolve-AzDoRepositoryPath' {

    It 'joins a reference to the directory of the referencing file' {
        InModuleScope PSAzureDevOpsGraph {
            Resolve-AzDoRepositoryPath -SourceDirectory 'pipelines' -Reference 'templates/x.yml' |
                Should-BeString 'pipelines/templates/x.yml'
        }
    }

    It 'ignores the source directory when the path is from a repository root' {
        InModuleScope PSAzureDevOpsGraph {
            Resolve-AzDoRepositoryPath -SourceDirectory 'deep/nested' -Reference 'templates/x.yml' -FromRepositoryRoot |
                Should-BeString 'templates/x.yml'
        }
    }

    It 'treats a leading slash as repository-root-relative' {
        InModuleScope PSAzureDevOpsGraph {
            Resolve-AzDoRepositoryPath -SourceDirectory 'pipelines' -Reference '/templates/x.yml' |
                Should-BeString 'templates/x.yml'
        }
    }

    It 'collapses . and .. rather than emitting them into an id' {
        InModuleScope PSAzureDevOpsGraph {
            Resolve-AzDoRepositoryPath -SourceDirectory 'a/b/c' -Reference '../../d/./e.yml' |
                Should-BeString 'a/d/e.yml'
        }
    }

    It 'does not climb above the repository root' {
        InModuleScope PSAzureDevOpsGraph {
            Resolve-AzDoRepositoryPath -SourceDirectory '' -Reference '../../x.yml' | Should-BeString 'x.yml'
        }
    }

    It 'normalises backslashes, which a hand-edited YAML file can carry' {
        InModuleScope PSAzureDevOpsGraph {
            Resolve-AzDoRepositoryPath -SourceDirectory 'p' -Reference 'templates\x.yml' |
                Should-BeString 'p/templates/x.yml'
        }
    }
}

Describe 'Add-AzDoGraphNode' {

    It 'is a no-op for an id already present, not a duplicate' {
        InModuleScope PSAzureDevOpsGraph {
            $nodes = [ordered]@{}
            Add-AzDoGraphNode -Node $nodes -Id 'repo:a' -Kind 'repo' -Name 'a'
            Add-AzDoGraphNode -Node $nodes -Id 'repo:a' -Kind 'repo' -Name 'a'
            $nodes.Count | Should-Be 1
        }
    }

    It 'writes repo on the two kinds that live somewhere, and path only on yaml' {
        InModuleScope PSAzureDevOpsGraph {
            $nodes = [ordered]@{}
            Add-AzDoGraphNode -Node $nodes -Id 'yaml:a/b.yml' -Kind 'yaml' -Name 'b.yml' -Repository 'a' -Path 'repos/a/b.yml'
            Add-AzDoGraphNode -Node $nodes -Id 'pipeline:P' -Kind 'pipeline' -Name 'P' -Repository 'a'
            Add-AzDoGraphNode -Node $nodes -Id 'repo:a' -Kind 'repo' -Name 'a' -Repository 'a'

            $nodes['yaml:a/b.yml'].path | Should-BeString 'repos/a/b.yml'
            # A pipeline node's repository is not readable from its id, so it is
            # a positive fact worth writing.
            $nodes['pipeline:P'].repo | Should-BeString 'a'
            $nodes['pipeline:P'].PSObject.Properties.Name | Should-NotContainCollection 'path'
            # A repo node's name already is the repository.
            $nodes['repo:a'].PSObject.Properties.Name | Should-BeCollection @('id', 'kind', 'name')
        }
    }
}

Describe 'Add-AzDoGraphEdge' {

    It 'omits an optional field there is nothing to say about' {
        InModuleScope PSAzureDevOpsGraph {
            $edges = [ordered]@{}
            Add-AzDoGraphEdge -Edge $edges -From 'a' -To 'b' -Kind 'definition'
            $names = $edges.Values[0].PSObject.Properties.Name
            $names | Should-BeCollection @('from', 'to', 'kind')
        }
    }

    It 'writes refKind only on an unresolved edge, where kind cannot carry it' {
        InModuleScope PSAzureDevOpsGraph {
            $edges = [ordered]@{}
            Add-AzDoGraphEdge -Edge $edges -From 'a' -To 'b' -Kind 'template' -Reference 'x.yml' -ReferenceKind 'template'
            Add-AzDoGraphEdge -Edge $edges -From 'a' -To 'c' -Kind 'unresolved' -Reference 'y.yml' -ReferenceKind 'template' -Reason 'file-not-found'

            $resolved = $edges.Values | Where-Object to -eq 'b'
            $unresolved = $edges.Values | Where-Object to -eq 'c'
            $resolved.PSObject.Properties.Name | Should-NotContainCollection 'refKind'
            $unresolved.PSObject.Properties.Name | Should-ContainCollection 'refKind'
        }
    }

    It 'de-duplicates on the whole edge, not on its endpoints' {
        InModuleScope PSAzureDevOpsGraph {
            $edges = [ordered]@{}
            Add-AzDoGraphEdge -Edge $edges -From 'a' -To 'b' -Kind 'template' -Reference 'x.yml'
            Add-AzDoGraphEdge -Edge $edges -From 'a' -To 'b' -Kind 'template' -Reference 'x.yml'
            Add-AzDoGraphEdge -Edge $edges -From 'a' -To 'b' -Kind 'template' -Reference 'other.yml'
            $edges.Count | Should-Be 2
        }
    }
}

Describe 'ConvertTo-AzDoHtmlText' {

    It 'escapes the five characters that break HTML or SVG' {
        InModuleScope PSAzureDevOpsGraph {
            ConvertTo-AzDoHtmlText '<a href="x">&' | Should-BeString '&lt;a href=&quot;x&quot;&gt;&amp;'
        }
    }

    It 'returns an empty string for null rather than the word null' {
        InModuleScope PSAzureDevOpsGraph {
            ConvertTo-AzDoHtmlText $null | Should-BeString ''
        }
    }
}

Describe 'ConvertFrom-AzDoYamlDocument' {

    It 'returns null for whitespace rather than throwing' {
        InModuleScope PSAzureDevOpsGraph {
            ConvertFrom-AzDoYamlDocument -Text '   ' | Should-BeNull
        }
    }

    It 'returns null for a document that will not parse' {
        InModuleScope PSAzureDevOpsGraph {
            ConvertFrom-AzDoYamlDocument -Text "a:`n  - b`n   - c: `"unterminated" | Should-BeNull
        }
    }
}

Describe 'Format-AzDoEdgeTitle' {

    It 'names only the optional fields the edge actually carries' {
        InModuleScope PSAzureDevOpsGraph {
            $edge = [pscustomobject]@{ from = 'a'; to = 'b'; kind = 'template'; ref = 'x.yml' }
            $title = Format-AzDoEdgeTitle -Edge $edge
            $title | Should-MatchString 'ref: x\.yml'
            $title | Should-NotMatchString 'reason'
        }
    }
}
