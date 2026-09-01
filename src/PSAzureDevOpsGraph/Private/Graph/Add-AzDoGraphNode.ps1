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
    # repo and path are required on a yaml node and are nothing to say on the
    # others, where the id and name already carry the same fact.
    if ($Kind -eq 'yaml') {
        $record['repo'] = $Repository
        $record['path'] = $Path
    }
    $Node[$Id] = [pscustomobject] $record
}
