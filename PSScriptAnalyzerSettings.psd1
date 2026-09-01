# At the repository root so editors, CI and the Lint task all lint identically.
@{
    # ParseError is listed EXPLICITLY, and its absence is the defect this line
    # exists to prevent. Invoke-ScriptAnalyzer -Settings filters diagnostics by
    # severity, and ParseError is its own severity outside Error. A settings
    # file listing only Error and Warning - the idiom every example shows -
    # silently drops every parse error, so the Lint task reports clean on a
    # source file that cannot be parsed at all and the build fails much later
    # against the generated psm1 instead.
    Severity     = @('ParseError', 'Error', 'Warning')

    # Empty deliberately. Every command in this module is a read verb, so
    # PSUseShouldProcessForStateChangingFunctions cannot fire, and no name here
    # is fixed by a contract another repository owns. A suppression with no
    # reason beside it is indistinguishable from a rule somebody could not get
    # to pass; there is nothing to suppress yet, so nothing is suppressed.
    ExcludeRules = @()

    Rules        = @{
        PSPlaceOpenBrace           = @{ Enable = $true; OnSameLine = $true }
        PSUseConsistentIndentation = @{ Enable = $true; IndentationSize = 4 }
    }
}
