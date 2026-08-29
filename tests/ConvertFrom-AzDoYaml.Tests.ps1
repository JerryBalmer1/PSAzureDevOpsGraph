#requires -Modules Pester

BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..' 'src' 'PSAzureDevOpsGraph'

    # The parser is private, and it is the component most likely to be wrong
    # and the one whose failures are least legible from outside. It has no
    # dependencies, so dot-source the file directly rather than reaching through
    # the module scope: one less layer between a failure and its cause.
    . (Join-Path $script:ModuleRoot 'Private' 'ConvertFrom-AzDoYaml.ps1')
}

Describe 'ConvertFrom-AzDoYaml' {

    It 'reads a flat mapping' {
        $doc = ConvertFrom-AzDoYaml -Text "trigger: none`npool: ubuntu"
        $doc['trigger'] | Should -Be 'none'
        $doc['pool']    | Should -Be 'ubuntu'
    }

    It 'reads a nested mapping' {
        $doc = ConvertFrom-AzDoYaml -Text "pool:`n  vmImage: ubuntu-latest"
        $doc['pool']['vmImage'] | Should -Be 'ubuntu-latest'
    }

    It 'reads a sequence of mappings and keeps it a collection when it has one entry' {
        $doc = ConvertFrom-AzDoYaml -Text "steps:`n  - script: a"
        @($doc['steps']).Count | Should -Be 1
        $doc['steps'][0]['script'] | Should -Be 'a'
    }

    It 'reads a sequence indented level with its key' {
        # Azure DevOps YAML is written both ways; both must parse the same.
        $doc = ConvertFrom-AzDoYaml -Text "steps:`n- script: a`n- script: b"
        @($doc['steps']).Count | Should -Be 2
    }

    It 'reads a multi-entry sequence of mappings' {
        $yaml = @'
repositories:
  - repository: one
    type: git
  - repository: two
    type: git
'@
        $doc = ConvertFrom-AzDoYaml -Text $yaml
        @($doc['repositories']).Count | Should -Be 2
        $doc['repositories'][1]['repository'] | Should -Be 'two'
    }

    It 'strips a full-line comment' {
        $doc = ConvertFrom-AzDoYaml -Text "# a comment`ntrigger: none"
        $doc['trigger'] | Should -Be 'none'
    }

    It 'strips a trailing comment but keeps a hash inside a value' {
        $doc = ConvertFrom-AzDoYaml -Text "a: value # trailing`nb: `"has # hash`""
        $doc['a'] | Should -Be 'value'
        $doc['b'] | Should -Be 'has # hash'
    }

    It 'treats a block scalar as opaque so its contents are never references' {
        $yaml = @'
steps:
  - script: |
      echo "template: not-a-reference.yml"
      echo "checkout: nope"
  - script: echo after
'@
        $doc = ConvertFrom-AzDoYaml -Text $yaml
        @($doc['steps']).Count | Should -Be 2
        $doc['steps'][0]['script'] | Should -Be ''
        $doc['steps'][1]['script'] | Should -Be 'echo after'
    }

    It 'reads a flow mapping' {
        $doc = ConvertFrom-AzDoYaml -Text 'extends: { template: a.yml@b }'
        $doc['extends']['template'] | Should -Be 'a.yml@b'
    }

    It 'does not mistake a colon inside a scalar for a mapping separator' {
        $doc = ConvertFrom-AzDoYaml -Text "steps:`n  - checkout: self`n  - script: a:b"
        $doc['steps'][0]['checkout'] | Should -Be 'self'
        $doc['steps'][1]['script']   | Should -Be 'a:b'
    }

    It 'returns sequences as ordinary arrays, not List[object]' {
        # On PowerShell 7.6.5 the array subexpression @($x) throws
        # 'Argument types do not match' when $x is a List[object]. Handing a
        # List to a caller hands them that. This pins the contract.
        $doc = ConvertFrom-AzDoYaml -Text "steps:`n  - script: a`n  - script: b"
        # Tested via GetType(), not Should -BeOfType: the pipeline would
        # enumerate the array and assert about its first element instead.
        $doc['steps'].GetType().IsArray | Should -BeTrue
        { @($doc['steps']) } | Should -Not -Throw
        @($doc['steps']).Count | Should -Be 2
    }

    It 'returns null for empty input' {
        ConvertFrom-AzDoYaml -Text '' | Should -BeNullOrEmpty
    }
}
