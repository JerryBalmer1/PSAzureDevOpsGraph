function Add-AzDoGraphEdge {
    <#
    .SYNOPSIS
        Add an edge to the graph, de-duplicated on its full identity.
    .DESCRIPTION
        Optional fields are written only where there is a positive fact to
        state. An absent optional field means NOT STATED, which is a different
        and quieter claim than writing an empty value, and the difference shows
        up as one difference per edge when scored against a hand-authored
        oracle.

        A definition edge carries no ref: it is a claim about the Azure DevOps
        project rather than about a file. refKind is written only on an
        unresolved edge, where kind is 'unresolved' and the kind of reference
        would otherwise be lost; on every other edge kind already IS the
        reference kind and a second copy states nothing new.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Edge,
        [Parameter(Mandatory)] [string] $From,
        [Parameter(Mandatory)] [string] $To,
        [Parameter(Mandatory)]
        [ValidateSet('definition', 'template', 'extends', 'pipelineResource', 'repositoryResource', 'checkout', 'unresolved')]
        [string] $Kind,
        [string] $Reference,
        [string] $ReferenceKind,
        [string] $Alias,
        [string] $Reason
    )

    $record = [ordered]@{
        from = $From
        to   = $To
        kind = $Kind
    }
    if ($Reference)                                  { $record['ref'] = $Reference }
    if ($Kind -eq 'unresolved' -and $ReferenceKind)  { $record['refKind'] = $ReferenceKind }
    if ($Alias)                                      { $record['alias'] = $Alias }
    if ($Reason)                                     { $record['reason'] = $Reason }

    $key = ($record.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '|'
    if ($Edge.Contains($key)) { return }
    $Edge[$key] = [pscustomobject] $record
}
