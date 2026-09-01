@{
    # ParseError is listed EXPLICITLY. Invoke-ScriptAnalyzer -Settings filters
    # diagnostics by severity, and ParseError is its own severity outside Error.
    # Severity = @('Error','Warning') silently drops every parse error, which
    # turns the Lint gate green on a source file that cannot be parsed at all.
    Severity     = @('ParseError', 'Error', 'Warning')

    ExcludeRules = @()

    Rules        = @{
        PSPlaceOpenBrace           = @{ Enable = $true; OnSameLine = $true }
        PSUseConsistentIndentation = @{ Enable = $true; IndentationSize = 4 }
    }
}
