function Join-AzDoRepoPath {
    <#
    .SYNOPSIS
        Resolves a reference path against the file that made it, within one repository.
    .DESCRIPTION
        A reference with no @alias resolves relative to the DIRECTORY OF THE FILE
        making it, not to the root of the repository. A repository can hold both
        templates/steps-build.yml and pipelines/templates/steps-build.yml, and a
        root-relative resolver does not error - it returns the wrong file,
        confidently.

        A leading / is the one root-relative form Azure DevOps accepts.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $BasePath,
        [Parameter(Mandatory)] [string] $Reference
    )

    $reference = $Reference -replace '\\', '/'

    if ($reference.StartsWith('/')) {
        $parts = $reference.TrimStart('/') -split '/'
    } else {
        $baseDirectory = ($BasePath -replace '\\', '/')
        $baseDirectory = if ($baseDirectory -match '/') { $baseDirectory -replace '/[^/]*$', '' } else { '' }
        $prefix = if ($baseDirectory) { ($baseDirectory -split '/') } else { @() }
        $parts = @($prefix) + @($reference -split '/')
    }

    $stack = [System.Collections.Generic.List[string]]::new()
    foreach ($part in $parts) {
        if ($part -eq '' -or $part -eq '.') { continue }
        if ($part -eq '..') {
            if ($stack.Count) { $stack.RemoveAt($stack.Count - 1) }
            continue
        }
        $stack.Add($part)
    }

    $stack -join '/'
}
