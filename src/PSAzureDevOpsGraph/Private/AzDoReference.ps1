Set-StrictMode -Version 3.0

<#
Reference construction and the recursive walk over a parsed document.

These are ordinary functions with named parameters rather than closures called
positionally. That is deliberate: an argument-binding mistake in a closure
surfaces as an exception attributed to the loop that called it, which is a poor
place to debug from.
#>

function ConvertTo-AzDoReference {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('template', 'extends', 'pipelineResource', 'repositoryResource', 'checkout')]
        [string] $Kind,

        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string] $Reference,

        [Parameter()][AllowNull()][string] $Alias,
        [Parameter()][AllowNull()][string] $Path,
        [Parameter()][int] $Line = 0,

        [Parameter()][AllowNull()][string] $SourceRepository,
        [Parameter()][AllowNull()][string] $SourcePath,

        [Parameter()][AllowNull()][string] $RepositoryName,
        [Parameter()][AllowNull()][string] $ResourceType,
        [Parameter()][AllowNull()][string] $RepositoryRef,
        [Parameter()][AllowNull()][string] $Source,
        [Parameter()][AllowNull()][string] $ResourceProject
    )

    [pscustomobject]@{
        PSTypeName       = 'PSAzureDevOpsGraph.Reference'
        Kind             = $Kind
        Reference        = $Reference
        Alias            = $Alias
        Path             = $Path
        Line             = $Line
        SourceRepository = $SourceRepository
        SourcePath       = $SourcePath
        RepositoryName   = $RepositoryName
        ResourceType     = $ResourceType
        RepositoryRef    = $RepositoryRef
        Source           = $Source
        ResourceProject  = $ResourceProject
    }
}

function Get-AzDoYamlMapValue {
    <#
        Read a key from a parsed node, returning $null when the node is not a
        mapping or the key is absent. Keeps the callers free of repeated
        type tests.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()] $Node,
        [Parameter(Mandatory)][string] $Key
    )

    if ($null -eq $Node) { return $null }
    if (-not ($Node -is [System.Collections.IDictionary])) { return $null }
    if (-not $Node.Contains($Key)) { return $null }

    return $Node[$Key]
}

function Get-AzDoYamlLine {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][AllowNull()] $Node,
        [Parameter(Mandatory)][string] $Key
    )

    $value = Get-AzDoYamlMapValue -Node $Node -Key ('__line__' + $Key)
    if ($null -eq $value) { return 0 }
    return [int]$value
}

function Find-AzDoInlineReference {
    <#
        Walk a parsed node collecting `template` and `checkout` references.

        SkipTemplateHere exists for the extends node: its own `template` is an
        extends reference and has already been recorded by the caller, but the
        rest of the extends subtree (its parameters, which may carry step
        lists) still holds ordinary template references.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()] $Node,
        [Parameter(Mandatory)] $Accumulator,

        [Parameter()][switch] $SkipTemplateHere,
        [Parameter()][AllowNull()][string] $SourceRepository,
        [Parameter()][AllowNull()][string] $SourcePath
    )

    if ($null -eq $Node) { return }

    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($rawKey in @($Node.Keys)) {
            $key = [string]$rawKey
            if ($key.StartsWith('__line__')) { continue }

            $value = $Node[$key]

            if ($key -eq 'template' -and ($value -is [string])) {
                if ($SkipTemplateHere) { continue }

                $split = Split-AzDoTemplateReference -Reference ([string]$value)
                $Accumulator.Add((ConvertTo-AzDoReference -Kind 'template' -Reference ([string]$value) `
                    -Alias $split.Alias -Path $split.Path `
                    -Line (Get-AzDoYamlLine -Node $Node -Key 'template') `
                    -SourceRepository $SourceRepository -SourcePath $SourcePath))
                continue
            }

            if ($key -eq 'checkout' -and ($value -is [string])) {
                $Accumulator.Add((ConvertTo-AzDoReference -Kind 'checkout' -Reference ([string]$value) `
                    -Alias ([string]$value) `
                    -Line (Get-AzDoYamlLine -Node $Node -Key 'checkout') `
                    -SourceRepository $SourceRepository -SourcePath $SourcePath))
                continue
            }

            Find-AzDoInlineReference -Node $value -Accumulator $Accumulator `
                -SourceRepository $SourceRepository -SourcePath $SourcePath
        }
        return
    }

    if (($Node -is [System.Collections.IEnumerable]) -and -not ($Node -is [string])) {
        foreach ($item in $Node) {
            Find-AzDoInlineReference -Node $item -Accumulator $Accumulator `
                -SourceRepository $SourceRepository -SourcePath $SourcePath
        }
    }
}
