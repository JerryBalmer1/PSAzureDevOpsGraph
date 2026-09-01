function Resolve-AzDoRepositoryPath {
    <#
    .SYNOPSIS
        Normalise a reference path to a repository-root-relative path.
    .DESCRIPTION
        Without an @alias a reference resolves relative to the DIRECTORY OF THE
        FILE making it, not to the root of the repository. A repository can hold
        both templates/steps-build.yml and pipelines/templates/steps-build.yml;
        a root-relative resolver does not error, it returns the wrong file,
        confidently.

        With an @alias the path is joined to the ROOT of the aliased repository,
        so SourceDirectory is not used at all.

        A leading / is root-relative in Azure Pipelines and is honoured here.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $SourceDirectory,
        [Parameter(Mandatory)] [string] $Reference,
        [switch] $FromRepositoryRoot
    )

    # A hand-edited YAML file can carry Windows separators; the graph speaks in
    # forward slashes throughout, so normalise once here.
    $ref = $Reference.Replace([char] 92, [char] 47)

    $combined = if ($FromRepositoryRoot -or $ref.StartsWith('/')) {
        $ref.TrimStart('/')
    } elseif ([string]::IsNullOrEmpty($SourceDirectory)) {
        $ref
    } else {
        "$($SourceDirectory.Trim('/'))/$ref"
    }

    $segments = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in ($combined -split '/')) {
        switch ($segment) {
            ''    { }
            '.'   { }
            '..'  { if ($segments.Count) { $segments.RemoveAt($segments.Count - 1) } }
            default { $segments.Add($segment) }
        }
    }
    $segments -join '/'
}
