function Get-AzDoYamlReferenceNode {
    <#
    .SYNOPSIS
        Walk a parsed YAML object graph and emit every pipeline reference in it.
    .DESCRIPTION
        Structural, never textual. A reference is a mapping KEY named exactly
        'template'; buildTemplate: is not template:, and a parameter whose VALUE
        looks like a path is not a reference. Substring matching on 'template:'
        invents an edge from a parameter, and parameter values are chosen to be
        real existing paths precisely so that the invented edge resolves and
        therefore looks correct.

        The WHOLE document is walked, not a hard-coded list of blocks. A
        template under variables: is still a template edge, and hard-coding
        steps/jobs/stages is the most tempting shortcut in the problem, covers
        the large majority of real references, and silently loses the rest.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Node,
        [string] $ParentKey
    )

    if ($null -eq $Node) { return }

    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in @($Node.Keys)) {
            $value = $Node[$key]
            $name = [string] $key

            switch -CaseSensitive ($name) {
                'template' {
                    if ($value -is [string]) {
                        # extends.template is an EXTENDS edge, not a template
                        # edge. Collapsing every reference into one "depends on"
                        # kind destroys the distinction the graph exists to make.
                        $kind = if ($ParentKey -eq 'extends') { 'extends' } else { 'template' }
                        New-AzDoReferenceRecord -Kind $kind -Reference $value
                    }
                }
                'checkout' {
                    if ($value -is [string]) {
                        # checkout: self produces NOTHING AT ALL, and neither
                        # does none. checkout of another repository is a
                        # dependency on that repository - not a template
                        # reference, and no template edge may be invented from
                        # it.
                        if ($value -notin 'self', 'none', '') {
                            New-AzDoReferenceRecord -Kind 'checkout' -Reference $value -Alias $value -Name $value
                        }
                    }
                }
                'repositories' {
                    if ($ParentKey -eq 'resources' -and $value -isnot [string]) {
                        foreach ($entry in @($value)) {
                            if ($entry -isnot [System.Collections.IDictionary]) { continue }
                            $repoName = [string] $entry['name']
                            if (-not $repoName) { continue }
                            New-AzDoReferenceRecord -Kind 'repositoryResource' `
                                -Reference $repoName `
                                -Alias ([string] $entry['repository']) `
                                -Name $repoName `
                                -Type ([string] $entry['type'])
                        }
                    }
                }
                'pipelines' {
                    if ($ParentKey -eq 'resources' -and $value -isnot [string]) {
                        foreach ($entry in @($value)) {
                            if ($entry -isnot [System.Collections.IDictionary]) { continue }
                            # source: names a pipeline DEFINITION, not a file.
                            $source = [string] $entry['source']
                            if (-not $source) { continue }
                            New-AzDoReferenceRecord -Kind 'pipelineResource' `
                                -Reference $source `
                                -Alias ([string] $entry['pipeline']) `
                                -Name $source
                        }
                    }
                }
            }

            # Descend regardless: a template can sit under any key at any depth.
            if ($name -notin 'repositories', 'pipelines' -or $ParentKey -ne 'resources') {
                Get-AzDoYamlReferenceNode -Node $value -ParentKey $name
            }
        }
        return
    }

    if ($Node -isnot [string] -and $Node -is [System.Collections.IEnumerable]) {
        foreach ($item in $Node) {
            Get-AzDoYamlReferenceNode -Node $item -ParentKey $ParentKey
        }
    }
}
