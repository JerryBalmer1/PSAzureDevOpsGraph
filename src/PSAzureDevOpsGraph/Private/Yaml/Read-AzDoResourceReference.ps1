function Read-AzDoResourceReference {
    <#
    .SYNOPSIS
        The references declared under a resources: mapping.
    .DESCRIPTION
        resources.repositories names a repository. resources.pipelines names a
        pipeline DEFINITION, not a file -- its source: is a definition name, and
        an implementation that treats it as a path invents a yaml node that does
        not exist.

        Both carry an alias that the rest of the document uses, and that alias is
        a property of the file which declared it rather than of the traversal.
    .PARAMETER Node
        The value of a resources: key.
    .OUTPUTS
        PSAzureDevOpsGraph.Reference
    #>
    [CmdletBinding()]
    [OutputType('PSAzureDevOpsGraph.Reference')]
    param([Parameter(Mandatory)] [AllowNull()] $Node)

    if ($Node -isnot [System.Collections.IDictionary]) { return }

    foreach ($entry in @($Node['repositories'])) {
        if ($entry -isnot [System.Collections.IDictionary]) { continue }
        $alias = [string] $entry['repository']
        if (-not $alias) { continue }
        $declaredName = [string] $entry['name']

        # name: may be written Project/Repo. The graph is project-scoped, so the
        # last segment is the repository.
        $repo = if ($declaredName) { ($declaredName -split '/')[-1] } else { $alias }
        $asWritten = if ($declaredName) { $declaredName } else { $alias }

        ConvertTo-AzDoReference -RefKind 'repositoryResource' -Ref $asWritten -Alias $alias -Target $repo
    }

    foreach ($entry in @($Node['pipelines'])) {
        if ($entry -isnot [System.Collections.IDictionary]) { continue }
        $alias = [string] $entry['pipeline']
        if (-not $alias) { continue }
        $source = [string] $entry['source']
        $asWritten = if ($source) { $source } else { $alias }

        ConvertTo-AzDoReference -RefKind 'pipelineResource' -Ref $asWritten -Alias $alias -Target $source
    }
}
