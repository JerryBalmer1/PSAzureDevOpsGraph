#Requires -Version 7.2

BeforeAll {
    . "$PSScriptRoot/../TestHelpers.ps1"
    $script:Module = Import-ModuleUnderTest
}

Describe 'Resolve-AzDoRelativePath' {

    It 'joins <Base> + <Ref> to <Expected>' -ForEach @(
        @{ Base = 'pipelines'; Ref = 'templates/x.yml'; Expected = 'pipelines/templates/x.yml' }
        @{ Base = ''; Ref = 'templates/x.yml'; Expected = 'templates/x.yml' }
        @{ Base = 'pipelines/sub'; Ref = '../x.yml'; Expected = 'pipelines/x.yml' }
        @{ Base = 'pipelines'; Ref = './x.yml'; Expected = 'pipelines/x.yml' }
        @{ Base = 'pipelines'; Ref = '/root.yml'; Expected = 'root.yml' }
        @{ Base = 'a/b/c'; Ref = '../../x.yml'; Expected = 'a/x.yml' }
        @{ Base = 'pipelines'; Ref = 'sub\win.yml'; Expected = 'pipelines/sub/win.yml' }
    ) {
        $actual = & $script:Module { param($b, $r) Resolve-AzDoRelativePath -BaseDirectory $b -Path $r } $Base $Ref
        $actual | Should-Be $Expected
    }

    It 'cannot climb above the repository root' {
        $actual = & $script:Module { Resolve-AzDoRelativePath -BaseDirectory 'a' -Path '../../../x.yml' }
        $actual | Should-Be 'x.yml'
    }
}

Describe 'Find-AzDoGraphCycle' {

    It 'finds a two-node cycle' {
        $edges = @(
            [pscustomobject]@{ from = 'a'; to = 'b' }
            [pscustomobject]@{ from = 'b'; to = 'a' }
        )
        $found = @(& $script:Module { param($e) Find-AzDoGraphCycle -Edge $e } $edges)
        $found.Count | Should-Be 1
        $found[0] | Should-MatchString 'a -> b -> a'
    }

    It 'reports NOTHING for a diamond, because a revisit is not a cycle' {
        # Two pipelines including one shared template arrive at it twice.
        # Calling that a cycle is the same defect as reporting none, in the
        # other direction.
        $edges = @(
            [pscustomobject]@{ from = 'p'; to = 'x' }
            [pscustomobject]@{ from = 'p'; to = 'y' }
            [pscustomobject]@{ from = 'x'; to = 'z' }
            [pscustomobject]@{ from = 'y'; to = 'z' }
        )
        @(& $script:Module { param($e) Find-AzDoGraphCycle -Edge $e } $edges).Count | Should-Be 0
    }

    It 'reports nothing for a plain chain' {
        $edges = @(
            [pscustomobject]@{ from = 'a'; to = 'b' }
            [pscustomobject]@{ from = 'b'; to = 'c' }
        )
        @(& $script:Module { param($e) Find-AzDoGraphCycle -Edge $e } $edges).Count | Should-Be 0
    }

    It 'terminates on a self-loop rather than recursing' {
        $edges = @([pscustomobject]@{ from = 'a'; to = 'a' })
        @(& $script:Module { param($e) Find-AzDoGraphCycle -Edge $e } $edges).Count | Should-Be 1
    }

    It 'accepts an empty edge list' {
        @(& $script:Module { Find-AzDoGraphCycle -Edge @() }).Count | Should-Be 0
    }
}

Describe 'ConvertFrom-AzDoYamlText' {

    It 'returns null for text that does not parse, rather than throwing' {
        # An unparseable file is data. The rest of the graph still builds.
        $result = & $script:Module { ConvertFrom-AzDoYamlText -Text "a:`n  - b`n   - c: [`n" }
        $result | Should-BeNull
    }

    It 'returns null for empty text' {
        $result = & $script:Module { ConvertFrom-AzDoYamlText -Text '' }
        $result | Should-BeNull
    }

    It 'parses a mapping' {
        $result = & $script:Module { ConvertFrom-AzDoYamlText -Text "a: 1`n" }
        $result['a'] | Should-Be 1
    }
}

Describe 'Get-AzDoAuthHeader' {

    It 'builds a Basic header with an empty username and never puts the PAT in a URL' {
        $saved = $env:AZDO_PAT
        try {
            $env:AZDO_PAT = 'test-token-value'
            $header = & $script:Module { Get-AzDoAuthHeader }
            $header.Authorization | Should-MatchString '^Basic '
            $decoded = [Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($header.Authorization -replace '^Basic '))
            $decoded | Should-Be ':test-token-value'
        } finally {
            $env:AZDO_PAT = $saved
        }
    }

    It 'throws naming the variable when it is unset' {
        $saved = $env:AZDO_PAT
        try {
            $env:AZDO_PAT = $null
            { & $script:Module { Get-AzDoAuthHeader } } | Should-Throw -ExceptionMessage '*AZDO_PAT*'
        } finally {
            $env:AZDO_PAT = $saved
        }
    }
}
