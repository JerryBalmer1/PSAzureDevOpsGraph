Set-StrictMode -Version 3.0

<#
Reference splitting and path arithmetic.

The two rules that make pipeline references hard live here:

    template: templates/steps-build.yml
        No alias. Resolves relative to the directory of the file that made the
        reference, inside that file's own repository.

    template: steps/common.yml@shared
        Aliased. Resolves from the ROOT of the repository bound to 'shared',
        never relative to the referencing file.

A fixture that has steps-build.yml at both pipelines/templates/ and templates/
exists precisely to catch an implementation that anchors both at the root, or
both relative. Getting this wrong yields a graph that is entirely plausible and
entirely wrong.
#>

function Split-AzDoTemplateReference {
    <#
        'steps/common.yml@shared' -> Path 'steps/common.yml', Alias 'shared'
        'templates/build.yml'     -> Path 'templates/build.yml', Alias $null
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Reference)

    $at = $Reference.IndexOf('@')

    if ($at -lt 0) {
        return [pscustomobject]@{ Path = $Reference.Trim(); Alias = $null }
    }

    return [pscustomobject]@{
        Path  = $Reference.Substring(0, $at).Trim()
        Alias = $Reference.Substring($at + 1).Trim()
    }
}

function Join-AzDoRepositoryPath {
    <#
        Combine a base directory with a reference path and normalise the
        result to a repository-rooted path with no leading slash.

        A reference beginning with '/' is anchored at the repository root even
        when it carries no alias -- that is Azure DevOps' rule, and a template
        path of '/templates/x.yml' means something different from
        'templates/x.yml'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $BaseDirectory,
        [Parameter(Mandatory)][AllowEmptyString()][string] $ReferencePath
    )

    $ref = $ReferencePath -replace '\\', '/'

    if ($ref.StartsWith('/')) {
        $combined = $ref.TrimStart('/')
    }
    else {
        $base = ($BaseDirectory -replace '\\', '/').Trim('/')
        $combined = if ($base.Length -eq 0) { $ref } else { "$base/$ref" }
    }

    # Resolve '.' and '..' textually. These are repository paths, not
    # filesystem paths, so Path.GetFullPath would drag in the current drive.
    $stack = New-Object System.Collections.Generic.List[string]
    foreach ($segment in $combined -split '/') {
        if ($segment -eq '' -or $segment -eq '.') { continue }
        if ($segment -eq '..') {
            if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) }
            continue
        }
        $stack.Add($segment)
    }

    return ($stack -join '/')
}

function Get-AzDoParentPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Path)

    $p = ($Path -replace '\\', '/').TrimStart('/')
    $i = $p.LastIndexOf('/')

    if ($i -lt 0) { return '' }
    return $p.Substring(0, $i)
}

function ConvertTo-AzDoRepositoryRelativePath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Path)

    return ($Path -replace '\\', '/').TrimStart('/')
}

function Get-AzDoShortRepositoryName {
    <#
        A resources.repositories entry names its repository as 'Repo' or as
        'Project/Repo'. Only the last segment identifies the repository within
        a project; the leading segment, when present, is the project.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Name)

    $n = $Name.Trim()
    $i = $n.LastIndexOf('/')

    if ($i -lt 0) { return $n }
    return $n.Substring($i + 1)
}

function Get-AzDoRepositoryProjectName {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Name)

    $n = $Name.Trim()
    $i = $n.LastIndexOf('/')

    if ($i -lt 0) { return '' }
    return $n.Substring(0, $i)
}

function Test-AzDoInventoryPath {
    <#
        Does this path exist in this repository, according to the inventory the
        graph walk built?

        An unknown repository answers $true rather than $false. The inventory is
        an optimisation, not an authority: when it has nothing to say about a
        repository, reporting "file not found" would invent a failure the
        project does not have. A missing file is only reported when the
        inventory positively knows the repository's contents.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowNull()][hashtable] $Inventory,
        [Parameter(Mandatory)][AllowEmptyString()][string] $RepositoryName,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Path
    )

    if ($null -eq $Inventory) { return $true }
    if (-not $Inventory.ContainsKey($RepositoryName)) { return $true }

    return $Inventory[$RepositoryName].Contains($Path.ToLowerInvariant())
}
