@{
    # At the repository root so editors and CI lint identically to the build.
    # ParseError is listed explicitly. Without it, Severity filtering drops
    # parse errors and the Lint gate goes green on a file that cannot be
    # parsed at all - which happened here: a hashtable entry using -f with two
    # arguments needs parentheses, and the build only caught it at Test time.
    Severity = @('ParseError', 'Error', 'Warning')

    ExcludeRules = @(
        # The module is read-only and every exported command is a Get-/Resolve-/
        # Export- verb with no side effect, so there is nothing for ShouldProcess
        # to guard.
        'PSUseShouldProcessForStateChangingFunctions'
    )

    Rules = @{
        PSPlaceOpenBrace           = @{ Enable = $true; OnSameLine = $true }
        PSUseConsistentIndentation = @{ Enable = $true; IndentationSize = 4 }
    }
}
