@{
    # The only place build dependencies are pinned. Every entry states a
    # RequiredVersion or a MinimumVersion; an unpinned dependency lets the
    # build change what it is testing between two runs.
    InvokeBuild        = @{ MinimumVersion = '5.10.0' }
    Pester             = @{ MinimumVersion = '5.5.0' }
    PSScriptAnalyzer   = @{ MinimumVersion = '1.21.0' }
    'powershell-yaml'  = @{ MinimumVersion = '0.4.7' }
}
