function Find-AzDoYamlReference {
    <#
    .SYNOPSIS
        Walks a parsed YAML object graph and emits every reference it contains.
    .DESCRIPTION
        Structural, never textual. A reference is a mapping KEY named exactly
        'template'; buildTemplate is not template, and a parameter whose VALUE
        looks like a path is not a reference.

        The whole document is walked rather than a hard-coded list of blocks. A
        template under variables is still a template edge, and hard-coding
        steps/jobs/stages is the most tempting shortcut in the problem: it covers
        the large majority of real references and silently loses the rest.
    .OUTPUTS
        PSAzureDevOpsGraph.Reference
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [object] $Node,
        [switch] $SkipTemplateKey
    )

    if ($null -eq $Node) { return }

    if ($Node -is [System.Collections.IDictionary]) {

        # extends -> template is an EXTENDS edge, not a template edge. Collapsing
        # every reference into one "depends on" kind destroys the distinction the
        # graph exists to make.
        if ($Node.Contains('extends') -and $Node['extends'] -is [System.Collections.IDictionary] -and
            $Node['extends'].Contains('template') -and $Node['extends']['template'] -is [string]) {
            Split-AzDoReference -Kind 'extends' -Reference ([string] $Node['extends']['template'])
        }

        if (-not $SkipTemplateKey -and $Node.Contains('template') -and $Node['template'] -is [string]) {
            Split-AzDoReference -Kind 'template' -Reference ([string] $Node['template'])
        }

        # checkout: self produces nothing at all. checkout of another repository
        # is a dependency on that REPOSITORY - no template edge may be invented
        # from it.
        if ($Node.Contains('checkout') -and $Node['checkout'] -is [string]) {
            $alias = [string] $Node['checkout']
            if ($alias -and $alias -ne 'self' -and $alias -ne 'none') {
                [pscustomobject] @{
                    PSTypeName = 'PSAzureDevOpsGraph.Reference'
                    Kind       = 'checkout'
                    Reference  = $alias
                    Path       = $null
                    Alias      = $alias
                    Repository = $null
                }
            }
        }

        if ($Node.Contains('resources') -and $Node['resources'] -is [System.Collections.IDictionary]) {
            $resources = $Node['resources']

            if ($resources.Contains('repositories')) {
                foreach ($entry in @($resources['repositories'])) {
                    if ($entry -isnot [System.Collections.IDictionary]) { continue }
                    $name = if ($entry.Contains('name')) { [string] $entry['name'] } else { $null }
                    if (-not $name) { continue }
                    [pscustomobject] @{
                        PSTypeName = 'PSAzureDevOpsGraph.Reference'
                        Kind       = 'repositoryResource'
                        Reference  = $name
                        Path       = $null
                        Alias      = if ($entry.Contains('repository')) { [string] $entry['repository'] } else { $null }
                        # A name may be project-qualified; the repository node is
                        # named for the repository, not for the qualification.
                        Repository = ($name -split '/')[-1]
                    }
                }
            }

            if ($resources.Contains('pipelines')) {
                foreach ($entry in @($resources['pipelines'])) {
                    if ($entry -isnot [System.Collections.IDictionary]) { continue }
                    $source = if ($entry.Contains('source')) { [string] $entry['source'] } else { $null }
                    if (-not $source) { continue }
                    # source names a DEFINITION, not a file.
                    [pscustomobject] @{
                        PSTypeName = 'PSAzureDevOpsGraph.Reference'
                        Kind       = 'pipelineResource'
                        Reference  = $source
                        Path       = $null
                        Alias      = if ($entry.Contains('pipeline')) { [string] $entry['pipeline'] } else { $null }
                        Repository = $null
                    }
                }
            }
        }

        foreach ($key in @($Node.Keys)) {
            $skip = ($key -eq 'extends')
            Find-AzDoYamlReference -Node $Node[$key] -SkipTemplateKey:$skip
        }
        return
    }

    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
        foreach ($item in $Node) {
            Find-AzDoYamlReference -Node $item
        }
    }
}
