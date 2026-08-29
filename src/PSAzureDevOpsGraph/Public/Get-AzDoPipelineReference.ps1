Set-StrictMode -Version 3.0

function Get-AzDoPipelineReference {
    <#
    .SYNOPSIS
        The references made by one pipeline YAML document.

    .DESCRIPTION
        Parses a single YAML document and returns every reference it makes:
        `template`, `extends`, `resources.repositories`, `resources.pipelines`
        and `checkout`.

        This command parses. It does not resolve, and it does not touch the
        network -- so it is testable against a file on disk with no credentials.
        Turning a reference into a repository and a path is
        Resolve-AzDoPipelineReference's job, and the two are separate because a
        reference that failed to parse and a reference that failed to resolve
        are different faults with different fixes.

        The `repositoryResource` references it returns are also the document's
        alias declarations: they are what Resolve-AzDoPipelineReference needs to
        interpret an `@alias` suffix. Aliases are per document and are not
        inherited by the templates a document includes.

    .PARAMETER Content
        The YAML text.

    .PARAMETER LiteralPath
        A file on disk to read the YAML from.

    .PARAMETER SourceRepository
        Name of the repository the document lives in. Carried onto each
        reference; not used for parsing.

    .PARAMETER SourcePath
        Path of the document within its repository. Carried through as above.

    .EXAMPLE
        Get-AzDoPipelineReference -LiteralPath ./azure-pipelines.yml

    .EXAMPLE
        $yaml | Get-AzDoPipelineReference | Where-Object Kind -eq 'extends'

    .OUTPUTS
        PSAzureDevOpsGraph.Reference, one per reference found.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Content', ValueFromPipeline)]
        [AllowEmptyString()]
        [string] $Content,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string] $LiteralPath,

        [Parameter()][string] $SourceRepository,
        [Parameter()][string] $SourcePath
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
                throw "No such YAML file: $LiteralPath"
            }
            $Content = Get-Content -LiteralPath $LiteralPath -Raw -ErrorAction Stop
            if (-not $PSBoundParameters.ContainsKey('SourcePath')) { $SourcePath = $LiteralPath }
        }

        $doc = ConvertFrom-AzDoYaml -Text $Content
        if ($null -eq $doc) { return }

        $found = New-Object System.Collections.Generic.List[object]

        # ---- resources.repositories --------------------------------------
        $resources = Get-AzDoYamlMapValue -Node $doc -Key 'resources'

        $repositories = Get-AzDoYamlMapValue -Node $resources -Key 'repositories'
        if ($null -ne $repositories) {
            foreach ($entry in @($repositories)) {
                if ($null -eq $entry) { continue }
                if (-not ($entry -is [System.Collections.IDictionary])) { continue }

                $alias = Get-AzDoYamlMapValue -Node $entry -Key 'repository'
                $name  = Get-AzDoYamlMapValue -Node $entry -Key 'name'
                $type  = Get-AzDoYamlMapValue -Node $entry -Key 'type'
                $gitRef= Get-AzDoYamlMapValue -Node $entry -Key 'ref'

                $found.Add((ConvertTo-AzDoReference -Kind 'repositoryResource' `
                    -Reference ([string]$name) -Alias ([string]$alias) `
                    -Line (Get-AzDoYamlLine -Node $entry -Key 'repository') `
                    -SourceRepository $SourceRepository -SourcePath $SourcePath `
                    -RepositoryName ([string]$name) `
                    -ResourceType $(if ($null -eq $type) { 'git' } else { [string]$type }) `
                    -RepositoryRef ([string]$gitRef)))
            }
        }

        # ---- resources.pipelines -----------------------------------------
        $pipelineResources = Get-AzDoYamlMapValue -Node $resources -Key 'pipelines'
        if ($null -ne $pipelineResources) {
            foreach ($entry in @($pipelineResources)) {
                if ($null -eq $entry) { continue }
                if (-not ($entry -is [System.Collections.IDictionary])) { continue }

                $alias   = Get-AzDoYamlMapValue -Node $entry -Key 'pipeline'
                $source  = Get-AzDoYamlMapValue -Node $entry -Key 'source'
                $inProj  = Get-AzDoYamlMapValue -Node $entry -Key 'project'

                $found.Add((ConvertTo-AzDoReference -Kind 'pipelineResource' `
                    -Reference ([string]$source) -Alias ([string]$alias) `
                    -Line (Get-AzDoYamlLine -Node $entry -Key 'pipeline') `
                    -SourceRepository $SourceRepository -SourcePath $SourcePath `
                    -Source ([string]$source) -ResourceType 'pipeline' `
                    -ResourceProject ([string]$inProj)))
            }
        }

        # ---- extends -----------------------------------------------------
        # Recorded before the general walk so that its `template` is reported
        # as an extends reference rather than an ordinary template one. The two
        # compose differently and the graph keeps them apart.
        $extends = Get-AzDoYamlMapValue -Node $doc -Key 'extends'
        if ($null -ne $extends -and ($extends -is [System.Collections.IDictionary]) -and $extends.Contains('template')) {
            $raw   = [string]$extends['template']
            $split = Split-AzDoTemplateReference -Reference $raw

            $found.Add((ConvertTo-AzDoReference -Kind 'extends' -Reference $raw `
                -Alias $split.Alias -Path $split.Path `
                -Line (Get-AzDoYamlLine -Node $extends -Key 'template') `
                -SourceRepository $SourceRepository -SourcePath $SourcePath))
        }

        # ---- template and checkout, everywhere else ----------------------
        if ($doc -is [System.Collections.IDictionary]) {
            foreach ($rawKey in @($doc.Keys)) {
                $key = [string]$rawKey
                if ($key.StartsWith('__line__')) { continue }
                if ($key -eq 'resources')        { continue }   # already handled

                $value = $doc[$key]

                if ($key -eq 'extends' -and $null -ne $extends) {
                    Find-AzDoInlineReference -Node $value -Accumulator $found -SkipTemplateHere `
                        -SourceRepository $SourceRepository -SourcePath $SourcePath
                    continue
                }

                if ($key -eq 'template' -and ($value -is [string])) {
                    $split = Split-AzDoTemplateReference -Reference ([string]$value)
                    $found.Add((ConvertTo-AzDoReference -Kind 'template' -Reference ([string]$value) `
                        -Alias $split.Alias -Path $split.Path `
                        -Line (Get-AzDoYamlLine -Node $doc -Key 'template') `
                        -SourceRepository $SourceRepository -SourcePath $SourcePath))
                    continue
                }

                Find-AzDoInlineReference -Node $value -Accumulator $found `
                    -SourceRepository $SourceRepository -SourcePath $SourcePath
            }
        }
        else {
            Find-AzDoInlineReference -Node $doc -Accumulator $found `
                -SourceRepository $SourceRepository -SourcePath $SourcePath
        }

        foreach ($reference in $found) { Write-Output $reference }
    }
}
