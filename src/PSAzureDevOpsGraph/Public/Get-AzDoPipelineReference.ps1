function Get-AzDoPipelineReference {
    <#
    .SYNOPSIS
        Extracts the references made by one pipeline YAML document.
    .DESCRIPTION
        Parsing only. No resolution and no network: this command answers "what
        does this file say", not "what does it point at". Those are separate
        because the first is testable against a file on disk with no credentials
        and the second is not, and because a combined command reports a
        resolution failure as though it were a parsing result, with no way to
        tell which half was wrong.

        Recognises template, extends, resources.repositories,
        resources.pipelines and checkout.
    .EXAMPLE
        Get-AzDoPipelineReference -Path ./azure-pipelines.yml
    .EXAMPLE
        Get-AzDoPipelineYaml -Organisation contoso -Project web -Definition 12 |
            Get-AzDoPipelineReference
    #>
    [CmdletBinding(DefaultParameterSetName = 'Yaml')]
    [OutputType('PSAzureDevOpsGraph.PipelineReference')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Yaml', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AllowEmptyString()]
        [Alias('Content')]
        [string]$Yaml,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$Path,

        # Provenance, carried onto every reference so that a resolver downstream
        # does not have to be told again which file it came from.
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$SourceRepository,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('SourceFile')]
        [string]$SourcePath
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "No such file: $Path" }
            $Yaml = Get-Content -LiteralPath $Path -Raw
            if (-not $SourcePath) { $SourcePath = $Path }
        }
        if ([string]::IsNullOrWhiteSpace($Yaml)) { return }

        $srcRepo = $SourceRepository
        $srcPath = $SourcePath

        $newReference = {
            param($Kind, $Reference, $RefPath, $Alias, $Fields, $Line)
            $f = if ($Fields) { $Fields } else { @{} }
            [pscustomobject]@{
                PSTypeName       = 'PSAzureDevOpsGraph.PipelineReference'
                Kind             = $Kind
                Reference        = $Reference
                Path             = $RefPath
                Alias            = $Alias
                Repository       = $f['repository']
                Name             = $f['name']
                Type             = $f['type']
                Ref              = $f['ref']
                Pipeline         = $f['pipeline']
                Source           = $f['source']
                Project          = $f['project']
                Line             = $Line
                SourceRepository = $srcRepo
                SourcePath       = $srcPath
            }
        }

        $stack   = [System.Collections.Generic.List[object]]::new()
        $pending = $null

        foreach ($token in (ConvertTo-AzDoYamlToken -Text $Yaml)) {
            while ($stack.Count -gt 0 -and $stack[$stack.Count - 1].Indent -ge $token.Indent) {
                $stack.RemoveAt($stack.Count - 1)
            }
            $context = @($stack | ForEach-Object { $_.Key })
            $parent  = if ($context.Count) { $context[-1] } else { $null }
            $grand   = if ($context.Count -ge 2) { $context[-2] } else { $null }

            $inRepositories = ($grand -eq 'resources' -and $parent -eq 'repositories')
            $inPipelines    = ($grand -eq 'resources' -and $parent -eq 'pipelines')

            if ($pending -and ($token.IsSequenceItem -or -not ($inRepositories -or $inPipelines) -or $token.Indent -lt $pending.Indent)) {
                $fields = $pending.Fields
                if ($pending.Type -eq 'repositories') {
                    if ($fields['name']) {
                        & $newReference 'repositoryResource' $fields['name'] $null $fields['repository'] $fields $pending.Line
                    }
                }
                elseif ($fields['source']) {
                    & $newReference 'pipelineResource' $fields['source'] $null $fields['pipeline'] $fields $pending.Line
                }
                $pending = $null
            }

            if ($inRepositories -or $inPipelines) {
                if ($token.IsSequenceItem) {
                    $pending = @{
                        Type   = if ($inRepositories) { 'repositories' } else { 'pipelines' }
                        Indent = $token.Indent
                        Line   = $token.Line
                        Fields = @{}
                    }
                }
                if ($pending -and $token.Key) { $pending.Fields[$token.Key] = $token.Value }
            }
            elseif ($token.Key -eq 'template' -and $token.Value -and $context -notcontains 'parameters') {
                $kind    = if ($parent -eq 'extends') { 'extends' } else { 'template' }
                $value   = $token.Value
                $alias   = $null
                $refPath = $value
                if ($value -match '^(?<p>[^@]+)@(?<a>.+)$') { $refPath = $Matches['p']; $alias = $Matches['a'] }
                & $newReference $kind $value $refPath $alias $null $token.Line
            }
            elseif ($token.Key -eq 'checkout' -and $token.Value) {
                $value = $token.Value
                $alias = if ($value -in @('self', 'none')) { $null } else { $value }
                & $newReference 'checkout' $value $null $alias $null $token.Line
            }

            if ($token.Key) { $stack.Add([pscustomobject]@{ Indent = $token.Indent; Key = $token.Key }) }
        }

        if ($pending) {
            $fields = $pending.Fields
            if ($pending.Type -eq 'repositories') {
                if ($fields['name']) {
                    & $newReference 'repositoryResource' $fields['name'] $null $fields['repository'] $fields $pending.Line
                }
            }
            elseif ($fields['source']) {
                & $newReference 'pipelineResource' $fields['source'] $null $fields['pipeline'] $fields $pending.Line
            }
        }
    }
}
