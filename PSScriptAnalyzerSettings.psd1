# At the repository root so editors, CI and build.ps1 lint identically.
@{
    # ParseError is listed EXPLICITLY.
    #
    # Invoke-ScriptAnalyzer -Settings filters diagnostics by severity, and
    # ParseError is its own severity outside Error. Severity = @('Error','Warning')
    # - the idiom every example shows - silently drops every parse error, so the
    # Lint gate reports clean on a file that cannot be parsed at all and the
    # build fails much later against the generated psm1 instead.
    Severity     = @('ParseError', 'Error', 'Warning')

    ExcludeRules = @()

    Rules        = @{
        PSPlaceOpenBrace           = @{ Enable = $true; OnSameLine = $true }
        PSUseConsistentIndentation = @{ Enable = $true; IndentationSize = 4 }
    }
}
