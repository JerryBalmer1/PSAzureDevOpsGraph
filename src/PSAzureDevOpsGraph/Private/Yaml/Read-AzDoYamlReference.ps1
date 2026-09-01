function Read-AzDoYamlReference {
    <#
    .SYNOPSIS
        Walk a parsed YAML object graph and emit every reference it makes.
    .DESCRIPTION
        Structural, never textual. The document is walked in FULL rather than
        through a hard-coded list of blocks -- a template under variables: is
        still a template edge, and hard-coding steps/jobs/stages covers the large
        majority of real references while silently losing the rest.

        A reference is a mapping key named EXACTLY template. buildTemplate: is
        not template:, and a substring match invents an edge from a parameter:
        parameter values are chosen to be real, existing paths precisely so that
        a text scan produces an edge that resolves and therefore looks correct.
        The value must also be a string; a template: key whose value is a mapping
        is not a path.
    .PARAMETER Node
        The parsed object graph, or a sub-tree of it during recursion.
    .PARAMETER InExtendsScope
        Set while walking the mapping that is the direct value of an extends:
        key, so its template: child is an extends edge rather than a template
        edge. Deliberately NOT carried into other keys of that mapping, so a
        template nested under extends.parameters is an ordinary template
        reference.
    .OUTPUTS
        PSAzureDevOpsGraph.Reference
    #>
    [CmdletBinding()]
    [OutputType('PSAzureDevOpsGraph.Reference')]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Node,
        [switch] $InExtendsScope
    )

    if ($null -eq $Node) { return }

    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in @($Node.Keys)) {
            $name = [string] $key
            $value = $Node[$key]

            # Exact, case-sensitive key match. Every branch here is an if rather
            # than a switch because continue inside a switch does not mean
            # "next key" and the difference is silent.
            if ($name -ceq 'template') {
                if ($value -is [string]) {
                    $kind = if ($InExtendsScope) { 'extends' } else { 'template' }
                    ConvertTo-AzDoReference -RefKind $kind -Ref $value
                } else {
                    Read-AzDoYamlReference -Node $value
                }
            } elseif ($name -ceq 'extends') {
                Read-AzDoYamlReference -Node $value -InExtendsScope
            } elseif ($name -ceq 'resources') {
                Read-AzDoResourceReference -Node $value
            } elseif ($name -ceq 'checkout') {
                # checkout: self and checkout: none produce NOTHING AT ALL. An
                # alias is a dependency on that repository -- and no template
                # edge may be invented from it. Checking a repository out to read
                # a script from it is ordinary; inventing a template dependency
                # produces an edge that is plausible, resolves, and is wrong.
                if ($value -is [string] -and $value -notin @('self', 'none')) {
                    ConvertTo-AzDoReference -RefKind 'checkout' -Ref $value -Alias $value
                }
            } else {
                Read-AzDoYamlReference -Node $value
            }
        }
        return
    }

    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
        foreach ($item in $Node) {
            Read-AzDoYamlReference -Node $item -InExtendsScope:$InExtendsScope
        }
    }
}
