#Requires -Version 7.2
<#
    Seals on a FINISHED iteration. Everything here is tagged PreTag and is
    excluded from the default Test task, so the build stays green while an
    iteration is half done -- which is most of what a build is for.

    What belongs here: claims no unit test can make, because they are about what
    the code must NEVER do, or about agreement between documents and code.
#>

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:Source = Join-Path $script:Root 'src/PSAzureDevOpsGraph'
    $script:Manifest = Import-PowerShellDataFile (Join-Path $script:Source 'PSAzureDevOpsGraph.psd1') -ErrorAction Stop

    $script:SourceFiles = @(Get-ChildItem $script:Source -Filter *.ps1 -Recurse -File)
    $script:AllSource = ($script:SourceFiles | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
}

Describe 'Read-only, permanently' -Tag 'PreTag' {

    It 'never issues a write method' {
        # Not behind a switch, not in a test. There is no -Force that changes
        # this. A tool that walks an organisation's pipelines is exactly the kind
        # of thing run with a high-privilege token.
        foreach ($file in $script:SourceFiles) {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $null, [ref] $errors)
            $writes = $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    $node.Value -in @('Post', 'Put', 'Patch', 'Delete', 'POST', 'PUT', 'PATCH', 'DELETE')
                }, $true)
            @($writes).Count | Should-Be 0 -Because "$($file.Name) must issue no write method"
        }
    }

    It 'names no pipeline run or queue route anywhere in source' {
        $script:AllSource | Should-NotMatchString '_apis/pipelines/[^\s]*/runs'
        $script:AllSource | Should-NotMatchString '_apis/build/builds'
    }

    It 'defines no function whose verb writes' {
        $writing = @('New', 'Set', 'Remove', 'Start', 'Stop', 'Restart', 'Update', 'Publish', 'Queue', 'Clear')
        foreach ($file in $script:SourceFiles) {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $null, [ref] $errors)
            foreach ($function in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
                $verb = ($function.Name -split '-')[0]
                $writing | Should-NotContainCollection $verb -Because "$($function.Name) in $($file.Name)"
            }
        }
    }

    It 'never puts the token in a URL or an output string' {
        $script:AllSource | Should-NotMatchString '://[^/\s"]*:\$env:AZDO_PAT'
        $script:AllSource | Should-NotMatchString 'Write-(Host|Output|Verbose|Warning)[^\r\n]*AZDO_PAT[^\r\n]*\$env'
    }

    It 'accepts no parameter that could carry a credential' {
        foreach ($file in $script:SourceFiles) {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $null, [ref] $errors)
            foreach ($parameter in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ParameterAst] }, $true)) {
                $name = $parameter.Name.VariablePath.UserPath
                $name | Should-NotMatchString '(?i)^(pat|token|credential|secret|password)$' -Because "in $($file.Name)"
            }
        }
    }
}

Describe 'Documents and code agree' -Tag 'PreTag' {

    It 'has an about_ topic in the culture directory' {
        Test-Path (Join-Path $script:Source 'en-US/about_PSAzureDevOpsGraph.help.txt') | Should-BeTrue
    }

    It 'names every exported command in the README command table' {
        $readme = Get-Content (Join-Path $script:Root 'README.md') -Raw
        foreach ($name in $script:Manifest.FunctionsToExport) {
            $readme | Should-MatchString ([regex]::Escape($name))
        }
    }

    It 'names no path in the README that does not exist' {
        $readme = Get-Content (Join-Path $script:Root 'README.md') -Raw
        $paths = [regex]::Matches($readme, '`(\./[^`\s]+)`') | ForEach-Object { $_.Groups[1].Value }
        foreach ($path in $paths) {
            Test-Path (Join-Path $script:Root ($path -replace '^\./', '')) | Should-BeTrue -Because "the README names $path"
        }
    }

    It 'pins every build dependency with a version' {
        $requirements = Import-PowerShellDataFile (Join-Path $script:Root 'Requirements.psd1') -ErrorAction Stop
        foreach ($entry in $requirements.GetEnumerator()) {
            $keys = @($entry.Value.Keys)
            ($keys -contains 'RequiredVersion' -or $keys -contains 'MinimumVersion') |
                Should-BeTrue -Because "$($entry.Key) must state a version"
        }
    }

    It 'does not pin build dependencies twice' {
        # Requirements.psd1 is the only place build dependencies are pinned;
        # RequiredModules is for runtime dependencies, which are a different
        # thing.
        $requirements = Import-PowerShellDataFile (Join-Path $script:Root 'Requirements.psd1') -ErrorAction Stop
        $runtime = @($script:Manifest.RequiredModules | ForEach-Object { $_['ModuleName'] })
        foreach ($name in @('InvokeBuild', 'Pester', 'PSScriptAnalyzer')) {
            if ($requirements.ContainsKey($name)) { $runtime | Should-NotContainCollection $name }
        }
    }
}
