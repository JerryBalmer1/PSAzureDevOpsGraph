<#
    Analyzer settings for PSAzureDevOpsGraph.

    Rules are excluded here, with a reason, rather than suppressed at the site
    that trips them. A suppression attribute in source is invisible from the
    outside and accumulates; an exclusion here has to be read by anyone changing
    these settings.
#>
@{
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # The module is a graph tool: plural nouns in output shapes ('nodes',
        # 'edges') are the domain's words, and the command nouns themselves are
        # singular as the rule intends.
        'PSUseSingularNouns'

        # Write-Host is used only by the build script for progress, where the
        # output is for a human watching a terminal and is not pipeline data.
        'PSAvoidUsingWriteHost'

        # The rule does not see through script blocks, so a parameter used only
        # inside one -- $Ref inside the fetch closure, $CoverageTarget inside a
        # task body -- is reported as unused. Every hit it produced here was
        # that false positive, and leaving it on would train the reader to
        # ignore it.
        'PSReviewUnusedParameter'
    )

    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('7.2')
        }
    }
}
