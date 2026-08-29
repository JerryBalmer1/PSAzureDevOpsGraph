function Add-AzDoYamlReferenceFromNode {
    <#
        .SYNOPSIS
            Recursive half of the reference walk. Adds what it finds to $Found.

        .DESCRIPTION
            Separated from Find-AzDoYamlReference so the recursion is an
            ordinary function call rather than a self-invoking scriptblock, and
            so the control flow around each key is explicit. An earlier version
            used switch/continue, whose meaning inside an enclosing foreach is
            ambiguous enough that a key could be both handled and walked again.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [AllowNull()] $Node,
        [AllowNull()] [string] $ParentKey,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]] $Found
    )

    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in @($Node.Keys)) {
            $value = $Node[$key]
            $name = [string] $key
            $handled = $false

            if ($name -eq 'parameters') {
                # Inputs, not references. Walking them is how a text scanner
                # invents an edge from a parameter default that happens to be a
                # real path.
                $handled = $true
            }
            elseif ($name -eq 'resources' -and $value -is [System.Collections.IDictionary]) {
                foreach ($entry in @($value['repositories'])) {
                    if ($entry -isnot [System.Collections.IDictionary]) { continue }
                    $alias = [string] $entry['repository']
                    if ([string]::IsNullOrWhiteSpace($alias)) { continue }
                    $Found.Add([pscustomobject]@{
                            RefKind = 'repositoryResource'
                            Ref     = [string] $entry['name']
                            Path    = $null
                            Alias   = $alias
                            Target  = ([string] $entry['name'] -split '/')[-1]
                        })
                }
                foreach ($entry in @($value['pipelines'])) {
                    if ($entry -isnot [System.Collections.IDictionary]) { continue }
                    $source = [string] $entry['source']
                    if ([string]::IsNullOrWhiteSpace($source)) { continue }
                    $Found.Add([pscustomobject]@{
                            RefKind = 'pipelineResource'
                            Ref     = $source
                            Path    = $null
                            Alias   = [string] $entry['pipeline']
                            Target  = $source
                        })
                }
                $handled = $true
            }
            elseif ($name -eq 'template' -and $value -is [string]) {
                $parts = $value -split '@', 2
                $Found.Add([pscustomobject]@{
                        RefKind = $(if ($ParentKey -eq 'extends') { 'extends' } else { 'template' })
                        Ref     = $value
                        Path    = $parts[0]
                        Alias   = $(if ($parts.Count -gt 1) { $parts[1] } else { $null })
                        Target  = $null
                    })
                $handled = $true
            }
            elseif ($name -eq 'checkout' -and $value -is [string]) {
                # 'self' is the pipeline's own repository and is a dependency on
                # nothing. 'none' checks out nothing at all.
                if ($value -ne 'self' -and $value -ne 'none') {
                    $Found.Add([pscustomobject]@{
                            RefKind = 'checkout'
                            Ref     = $value
                            Path    = $null
                            Alias   = $value
                            Target  = $null
                        })
                }
                $handled = $true
            }

            if (-not $handled) {
                Add-AzDoYamlReferenceFromNode -Node $value -ParentKey $name -Found $Found
            }
        }
    }
    elseif ($Node -is [System.Collections.IList] -and $Node -isnot [string]) {
        foreach ($item in $Node) {
            Add-AzDoYamlReferenceFromNode -Node $item -ParentKey $ParentKey -Found $Found
        }
    }
}

function Find-AzDoYamlReference {
    <#
        .SYNOPSIS
            Walks a parsed pipeline document and collects every reference in it.

        .DESCRIPTION
            Structural, never textual. A reference is a mapping key named
            exactly 'template' - which is why 'buildTemplate:' produces nothing,
            and why a parameter whose value happens to be a real template path
            is not a reference to anything.

            The whole document is walked rather than a hard-coded list of
            blocks, so a template under 'variables' is found. Hard-coding steps,
            jobs and stages covers the large majority of real references and
            silently loses the rest.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Document
    )

    $found = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Document) {
        Add-AzDoYamlReferenceFromNode -Node $Document -ParentKey $null -Found $found
    }
    , $found
}
