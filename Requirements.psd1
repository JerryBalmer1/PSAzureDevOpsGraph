<#
    Build dependencies, pinned, in one place.

    Nothing else in the repository names a version of these. A version pinned in
    two files is a version that will disagree with itself, and the disagreement
    shows up as a build that passes on one machine and fails on another for a
    reason nobody can see from either file.

    These are BUILD dependencies. The module itself has no runtime dependency on
    any of them -- see RequiredModules in the manifest, which is empty and is
    meant to stay that way.
#>
@{
    Pester           = '6.1.0'
    PSScriptAnalyzer = '1.25.0'
    InvokeBuild      = '5.14.23'
}
