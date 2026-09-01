function Get-AzDoCachedYaml {
    <#
    .SYNOPSIS
        Fetch a YAML file once per graph run, memoised on repository and path.
    .DESCRIPTION
        Resolution asks whether a file exists and assembly then asks for its
        text. Without a cache that is two round trips per reference, and a
        template included by six pipelines is fetched twelve times. The cache
        also records a miss, so a file that is not there is asked for once.

        $null means the file is not in that repository. That is a RESULT for a
        dependency graph, not an error.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Cache,
        [Parameter(Mandatory)] [string] $Organisation,
        [Parameter(Mandatory)] [string] $Project,
        [Parameter(Mandatory)] [string] $Repository,
        [Parameter(Mandatory)] [string] $Path,
        [string] $Ref
    )

    $key = "$Repository/$Path"
    if ($Cache.Contains($key)) { return $Cache[$key] }

    $parameter = @{
        Organisation = $Organisation
        Project      = $Project
        Repository   = $Repository
        Path         = $Path
    }
    if ($Ref) { $parameter['Ref'] = $Ref }

    $yaml = Get-AzDoPipelineYaml @parameter
    $Cache[$key] = if ($yaml) { [string] $yaml.Content } else { $null }
    $Cache[$key]
}
