@{
    # The ONLY place build dependencies are pinned. Runtime dependencies belong
    # in the manifest's RequiredModules, which is a different thing.
    InvokeBuild       = @{ MinimumVersion = '5.10.0' }

    # RequiredVersion, not MinimumVersion. Pester 5 and 6 disagree on assertion
    # syntax, discovery and mocking, and 5.7.1 is also installed on this machine.
    # A bare Invoke-Pester picks one silently.
    Pester            = @{ RequiredVersion = '6.1.0' }

    PSScriptAnalyzer  = @{ MinimumVersion = '1.21.0' }
    'powershell-yaml' = @{ MinimumVersion = '0.4.7' }
}
