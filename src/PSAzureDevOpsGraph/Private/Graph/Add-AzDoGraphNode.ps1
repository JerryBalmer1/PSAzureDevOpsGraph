function Add-AzDoGraphNode {
    <#
    .SYNOPSIS
        Add a node to the graph, keyed by identity.
    .DESCRIPTION
        A node is identified by WHAT IT IS, not by where a traversal reached it.
        Adding a node that already exists is a no-op, not a duplicate: building
        a tree per pipeline and concatenating gives two nodes for a template two
        pipelines include, the count inflates, and every metric computed from
        the graph is then wrong in the direction that looks busiest.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Node,
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [ValidateSet('pipeline', 'yaml', 'repo')] [string] $Kind,
        [Parameter(Mandatory)] [string] $Name,
        [string] $Repository,
        [string] $Path
    )

    if ($Node.Contains($Id)) { return }

    $record = [ordered]@{
        id   = $Id
        kind = $Kind
        name = $Name
    }
    # A pipeline and a yaml node both live somewhere, and which repository that
    # is cannot be read off the id of a pipeline node - only off its definition
    # edge, which is a different record. It is a positive fact about the node,
    # so it is written. A repo node's own name already is the repository, so
    # repeating it there would state nothing.
    if ($Kind -in 'yaml', 'pipeline') {
        $record['repo'] = $Repository
    }
    if ($Kind -eq 'yaml') {
        $record['path'] = $Path
    }
    $Node[$Id] = [pscustomobject] $record
}
