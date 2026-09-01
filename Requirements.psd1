# The only place build dependencies are pinned.
#
# Runtime dependencies are a different thing and are declared in the manifest's
# RequiredModules. powershell-yaml is both: the build parses YAML fixtures in
# its tests, and the module parses YAML at run time.
@{
    InvokeBuild       = @{ MinimumVersion = '5.10.0' }
    Pester            = @{ RequiredVersion = '6.1.0' }
    PSScriptAnalyzer  = @{ MinimumVersion = '1.21.0' }
    'powershell-yaml' = @{ MinimumVersion = '0.4.7' }
}
