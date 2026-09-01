# Build dependencies, and the only place they are pinned.
#
# Runtime dependencies are a different thing and live in the manifest's
# RequiredModules: PSAzureDevOpsGraph parses YAML with powershell-yaml at run
# time, so a machine that imports this module needs it whether or not it ever
# runs a build. Writing a dependency in both files creates two facts that must
# agree and are edited in different places.
@{
    InvokeBuild      = @{ MinimumVersion = '5.10.0' }

    # Pinned, not floored. Pester 5 and 6 disagree on assertion syntax,
    # discovery and mocking, and several 5.x versions are usually also
    # installed; a floor lets a bare resolve pick either one silently.
    Pester           = @{ RequiredVersion = '6.1.0' }

    PSScriptAnalyzer = @{ MinimumVersion = '1.21.0' }
}
