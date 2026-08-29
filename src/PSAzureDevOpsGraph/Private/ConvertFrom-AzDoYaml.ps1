Set-StrictMode -Version 3.0

<#
An indentation-aware parser for the subset of YAML that Azure DevOps pipeline
files use: block mappings, block sequences, scalars, flow collections, and
block scalars.

It is deliberately not a general YAML implementation. It exists so that
Get-AzDoPipelineReference can tell a step's `template:` from an `extends:`
template, and so that a `template:` appearing inside a shell script cannot be
mistaken for a reference. Block scalars are therefore consumed as opaque text
and their contents are never scanned:

    - script: |
        echo "template: not-a-reference.yml"

A regex over the raw file reports that line as a template reference. That is
the specific wrong answer this parser exists to avoid.
#>

function Split-AzDoYamlComment {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $inSingle = $false
    $inDouble = $false

    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]

        if ($c -eq "'" -and -not $inDouble) { $inSingle = -not $inSingle; continue }
        if ($c -eq '"' -and -not $inSingle) { $inDouble = -not $inDouble; continue }

        if ($c -eq '#' -and -not $inSingle -and -not $inDouble) {
            # A '#' begins a comment only at the start of the value or after
            # whitespace. 'a#b' is a scalar that contains a hash.
            if ($i -eq 0 -or [char]::IsWhiteSpace($Text[$i - 1])) {
                return $Text.Substring(0, $i).TrimEnd()
            }
        }
    }

    return $Text
}

function Find-AzDoYamlSeparator {
    <#
        Index of the ':' separating a mapping key from its value, or -1.

        Ignores ':' inside quotes and inside flow collections, and any ':' not
        followed by whitespace or end-of-string. That last rule is what keeps
        a bare sequence item such as '- self' or a URL scalar from being read
        as a mapping entry.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $depth    = 0
    $inSingle = $false
    $inDouble = $false

    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]

        if ($c -eq "'" -and -not $inDouble) { $inSingle = -not $inSingle; continue }
        if ($c -eq '"' -and -not $inSingle) { $inDouble = -not $inDouble; continue }
        if ($inSingle -or $inDouble) { continue }

        if ($c -eq '[' -or $c -eq '{') { $depth++; continue }
        if ($c -eq ']' -or $c -eq '}') { $depth--; continue }

        if ($c -eq ':' -and $depth -eq 0) {
            if ($i -eq $Text.Length - 1) { return $i }
            if ([char]::IsWhiteSpace($Text[$i + 1])) { return $i }
        }
    }

    return -1
}

function Split-AzDoYamlFlow {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $parts    = New-Object System.Collections.Generic.List[string]
    $depth    = 0
    $inSingle = $false
    $inDouble = $false
    $start    = 0

    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]

        if ($c -eq "'" -and -not $inDouble) { $inSingle = -not $inSingle; continue }
        if ($c -eq '"' -and -not $inSingle) { $inDouble = -not $inDouble; continue }
        if ($inSingle -or $inDouble) { continue }

        if ($c -eq '[' -or $c -eq '{') { $depth++; continue }
        if ($c -eq ']' -or $c -eq '}') { $depth--; continue }

        if ($c -eq ',' -and $depth -eq 0) {
            $parts.Add($Text.Substring($start, $i - $start).Trim())
            $start = $i + 1
        }
    }

    $parts.Add($Text.Substring($start).Trim())

    # No ',' here, unlike the block readers: every caller iterates these parts,
    # so they should arrive enumerated. Protecting the collection instead binds
    # the whole array to the loop variable on the first pass.
    return $parts.ToArray()
}

function ConvertFrom-AzDoYamlScalar {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $t = $Text.Trim()

    if ($t.Length -eq 0)                  { return '' }
    if ($t -eq '~' -or $t -eq 'null')     { return $null }
    if ($t -eq 'true'  -or $t -eq 'True') { return $true }
    if ($t -eq 'false' -or $t -eq 'False'){ return $false }

    if ($t.Length -ge 2) {
        if ($t[0] -eq '"' -and $t[$t.Length - 1] -eq '"') {
            return $t.Substring(1, $t.Length - 2)
        }
        if ($t[0] -eq "'" -and $t[$t.Length - 1] -eq "'") {
            return $t.Substring(1, $t.Length - 2).Replace("''", "'")
        }
    }

    # Flow collections. Pipeline YAML uses these for things like
    # `extends: { template: x.yml }` and short parameter lists.
    if ($t.Length -ge 2 -and $t[0] -eq '[' -and $t[$t.Length - 1] -eq ']') {
        $inner = $t.Substring(1, $t.Length - 2).Trim()
        if ($inner.Length -eq 0) { return @() }
        return @(Split-AzDoYamlFlow -Text $inner | ForEach-Object { ConvertFrom-AzDoYamlScalar -Text $_ })
    }

    if ($t.Length -ge 2 -and $t[0] -eq '{' -and $t[$t.Length - 1] -eq '}') {
        $map   = [ordered]@{}
        $inner = $t.Substring(1, $t.Length - 2).Trim()
        if ($inner.Length -eq 0) { return $map }

        foreach ($part in Split-AzDoYamlFlow -Text $inner) {
            $idx = Find-AzDoYamlSeparator -Text $part
            if ($idx -lt 0) { continue }
            $k = [string](ConvertFrom-AzDoYamlScalar -Text $part.Substring(0, $idx))
            $map[$k] = ConvertFrom-AzDoYamlScalar -Text $part.Substring($idx + 1)
        }
        return $map
    }

    return $t
}

function ConvertTo-AzDoYamlToken {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $tokens = New-Object System.Collections.Generic.List[object]
    $lines  = $Text -split "`r?`n"

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        if ($line -match '^\s*$')          { continue }
        if ($line -match '^\s*#')          { continue }
        if ($line -match '^\s*---\s*$')    { continue }
        if ($line -match '^\s*\.\.\.\s*$') { continue }

        $trimmed = $line.TrimStart()
        $indent  = $line.Length - $trimmed.Length

        $tokens.Add([pscustomobject]@{
            Indent = $indent
            Text   = $trimmed.TrimEnd()
            Line   = $i + 1
        })
    }

    # Two things are load-bearing here and in the other collection returns.
    #
    # ToArray(): callers get an ordinary PowerShell array. On PowerShell 7.6.5
    # the array subexpression @($x) throws 'Argument types do not match' when
    # $x is a List[object] -- .Count, foreach and the pipeline all work, only
    # @() fails -- so handing a List to a caller hands them a landmine.
    #
    # ',': stops PowerShell enumerating the result on the way out. Without it a
    # one-element sequence returns as a bare scalar and every caller that
    # indexes [0] gets the wrong thing.
    return ,$tokens.ToArray()
}

function Read-AzDoYamlMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tokens,
        [Parameter(Mandatory)][ref] $Cursor,
        [Parameter(Mandatory)][int] $Indent
    )

    $map = [ordered]@{}

    while ($Cursor.Value -lt $Tokens.Count) {
        $t = $Tokens[$Cursor.Value]

        if ($t.Indent -ne $Indent) { break }
        if ($t.Text -eq '-' -or $t.Text.StartsWith('- ')) { break }

        $sep = Find-AzDoYamlSeparator -Text $t.Text
        if ($sep -lt 0) {
            # Neither a mapping entry nor a sequence item. Unmodelled YAML;
            # skip the line rather than throwing away the whole document.
            $Cursor.Value++
            continue
        }

        $key     = [string](ConvertFrom-AzDoYamlScalar -Text $t.Text.Substring(0, $sep))
        $rest    = Split-AzDoYamlComment -Text $t.Text.Substring($sep + 1).Trim()
        $keyLine = $t.Line
        $Cursor.Value++

        if ($rest -match '^[|>][-+]?[0-9]*$') {
            # Block scalar. Consume every more-indented token unexamined.
            while ($Cursor.Value -lt $Tokens.Count -and $Tokens[$Cursor.Value].Indent -gt $t.Indent) {
                $Cursor.Value++
            }
            $map[$key] = ''
        }
        elseif ($rest.Length -eq 0) {
            if ($Cursor.Value -lt $Tokens.Count -and $Tokens[$Cursor.Value].Indent -gt $t.Indent) {
                $map[$key] = Read-AzDoYamlBlock -Tokens $Tokens -Cursor $Cursor -Indent $Tokens[$Cursor.Value].Indent
            }
            elseif ($Cursor.Value -lt $Tokens.Count -and
                    $Tokens[$Cursor.Value].Indent -eq $t.Indent -and
                    ($Tokens[$Cursor.Value].Text -eq '-' -or $Tokens[$Cursor.Value].Text.StartsWith('- '))) {
                # A block sequence may sit at the same indent as its key.
                $map[$key] = Read-AzDoYamlSequence -Tokens $Tokens -Cursor $Cursor -Indent $t.Indent
            }
            else {
                $map[$key] = $null
            }
        }
        else {
            $map[$key] = ConvertFrom-AzDoYamlScalar -Text $rest
        }

        # Line numbers are kept out of band under a key no pipeline schema
        # uses, so reference output can carry them without colliding.
        $map['__line__' + $key] = $keyLine
    }

    return $map
}

function Read-AzDoYamlSequence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tokens,
        [Parameter(Mandatory)][ref] $Cursor,
        [Parameter(Mandatory)][int] $Indent
    )

    $list = New-Object System.Collections.Generic.List[object]

    while ($Cursor.Value -lt $Tokens.Count) {
        $t = $Tokens[$Cursor.Value]

        if ($t.Indent -ne $Indent) { break }
        if (-not ($t.Text -eq '-' -or $t.Text.StartsWith('- '))) { break }

        if ($t.Text -eq '-') {
            $Cursor.Value++
            if ($Cursor.Value -lt $Tokens.Count -and $Tokens[$Cursor.Value].Indent -gt $Indent) {
                $list.Add((Read-AzDoYamlBlock -Tokens $Tokens -Cursor $Cursor -Indent $Tokens[$Cursor.Value].Indent))
            }
            else {
                $list.Add($null)
            }
            continue
        }

        $after       = $t.Text.Substring(2)
        $inner       = $after.TrimStart()
        $innerIndent = $t.Indent + 2 + ($after.Length - $inner.Length)

        if ($inner -eq '-' -or $inner.StartsWith('- ')) {
            $Tokens[$Cursor.Value] = [pscustomobject]@{
                Indent = $innerIndent
                Text   = $inner
                Line   = $t.Line
            }
            $list.Add((Read-AzDoYamlSequence -Tokens $Tokens -Cursor $Cursor -Indent $innerIndent))
        }
        elseif ((Find-AzDoYamlSeparator -Text $inner) -ge 0) {
            # '- key: value' opens a mapping whose keys sit at the column of
            # 'key'. Rewrite the token in place and let the mapping reader
            # continue from there; the next '- ' is less indented, so it stops.
            $Tokens[$Cursor.Value] = [pscustomobject]@{
                Indent = $innerIndent
                Text   = $inner
                Line   = $t.Line
            }
            $list.Add((Read-AzDoYamlMapping -Tokens $Tokens -Cursor $Cursor -Indent $innerIndent))
        }
        else {
            $list.Add((ConvertFrom-AzDoYamlScalar -Text (Split-AzDoYamlComment -Text $inner)))
            $Cursor.Value++
        }
    }

    return ,$list.ToArray()
}

function Read-AzDoYamlBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tokens,
        [Parameter(Mandatory)][ref] $Cursor,
        [Parameter(Mandatory)][int] $Indent
    )

    if ($Cursor.Value -ge $Tokens.Count) { return $null }

    $first = $Tokens[$Cursor.Value]
    if ($first.Text -eq '-' -or $first.Text.StartsWith('- ')) {
        $seq = Read-AzDoYamlSequence -Tokens $Tokens -Cursor $Cursor -Indent $Indent
        return ,$seq
    }

    $map = Read-AzDoYamlMapping -Tokens $Tokens -Cursor $Cursor -Indent $Indent
    return ,$map
}

function ConvertFrom-AzDoYaml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $tokens = ConvertTo-AzDoYamlToken -Text $Text
    if ($tokens.Count -eq 0) { return $null }

    $cursor = [ref] 0
    $doc = Read-AzDoYamlBlock -Tokens $tokens -Cursor $cursor -Indent $tokens[0].Indent
    return ,$doc
}
