function ConvertTo-AzDoYamlToken {
    <#
    .SYNOPSIS
        Reduces pipeline YAML to indent-aware key/value tokens.
    .DESCRIPTION
        Deliberately not a general YAML parser. Azure Pipelines YAML is a small,
        regular subset, and the references this module cares about -- template,
        extends, resources.repositories, resources.pipelines, checkout -- are all
        plain scalar keys in block mappings. A line scanner that understands
        indentation, block sequences and quoting covers them without adding a
        dependency the module would then have to ship.

        Anything it cannot classify is dropped rather than guessed at: a token it
        does not emit becomes a reference the graph does not claim, which is a
        safer failure than a reference it invents.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $lineNumber = 0
    foreach ($rawLine in ($Text -split "`r?`n")) {
        $lineNumber++
        $line = $rawLine

        # Strip a trailing comment, but only a '#' that is outside quotes and
        # either starts the line or follows whitespace. '#' inside a value --
        # 'refs/heads/feature#1' -- is not a comment.
        $inSingle = $false; $inDouble = $false; $cut = -1
        for ($i = 0; $i -lt $line.Length; $i++) {
            $c = $line[$i]
            if ($c -eq "'" -and -not $inDouble) { $inSingle = -not $inSingle }
            elseif ($c -eq '"' -and -not $inSingle) { $inDouble = -not $inDouble }
            elseif ($c -eq '#' -and -not $inSingle -and -not $inDouble) {
                if ($i -eq 0 -or [char]::IsWhiteSpace($line[$i - 1])) { $cut = $i; break }
            }
        }
        if ($cut -ge 0) { $line = $line.Substring(0, $cut) }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.TrimStart() -match '^(---|\.\.\.)\s*$') { continue }

        $indent  = $line.Length - $line.TrimStart(' ').Length
        $content = $line.TrimStart(' ')
        $isSequenceItem = $false

        # A block sequence entry may carry its first key inline: '- template: x'.
        # The key's effective indent is where the key actually starts, so that a
        # sibling key on the next line lines up with it.
        if ($content -match '^-(\s|$)') {
            $isSequenceItem = $true
            $rest    = $content.Substring(1)
            $lead    = $rest.Length - $rest.TrimStart(' ').Length
            $indent  = $indent + 1 + $lead
            $content = $rest.TrimStart(' ')
            if ([string]::IsNullOrWhiteSpace($content)) {
                # A bare '-': the mapping's keys follow on later lines.
                [pscustomobject]@{
                    Line = $lineNumber; Indent = $indent; IsSequenceItem = $true
                    Key  = $null; Value = $null; Raw = $rawLine
                }
                continue
            }
        }

        if ($content -notmatch '^(?<key>[A-Za-z_][A-Za-z0-9_.\-]*)\s*:(?:\s+(?<value>.*))?$') { continue }

        $key   = $Matches['key']
        $value = if ($Matches.ContainsKey('value')) { $Matches['value'] } else { '' }
        $value = $value.Trim()
        if ($value.Length -ge 2) {
            if (($value[0] -eq '"' -and $value[-1] -eq '"') -or ($value[0] -eq "'" -and $value[-1] -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }

        [pscustomobject]@{
            Line = $lineNumber; Indent = $indent; IsSequenceItem = $isSequenceItem
            Key  = $key; Value = $value; Raw = $rawLine
        }
    }
}
