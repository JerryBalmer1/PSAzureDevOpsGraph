# PSAzureDevOpsGraph

A PowerShell module for working out which Azure DevOps pipelines depend on what.

## The problem

Azure DevOps pipeline YAML composes by reference. A pipeline pulls in templates,
templates pull in other templates, and those references cross repository
boundaries. None of it is visible from any one file.

So the question nobody here can answer is: **if I change this template, which
pipelines break?** We have templates nobody will touch because no one can say
what depends on them, and pipelines nobody can account for.

## Using it

```powershell
$env:AZDO_PAT = '<a token with Code (read) and Build (read)>'

Import-Module ./src/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psd1

$graph = Get-AzDoPipelineDependencyGraph -Organisation contoso -Project Platform

# What could not be resolved -- usually the interesting part
$graph.edges | Where-Object kind -eq 'unresolved' |
    Format-Table from, ref, reason -AutoSize

# Everything that reaches a given template, directly
$graph.edges | Where-Object to -eq 'yaml:templates-shared/steps/common.yml'

$graph | Export-AzDoPipelineDependencyGraph -Path graph.json
$graph | Export-AzDoPipelineDependencyGraph -Path graph.html -Format Html
$graph | Export-AzDoPipelineDependencyGraph -Path graph.dot  -Format Dot
```

## Commands

| Command | Does |
|---|---|
| `Get-AzDoRepository` | The Git repositories in a project, empty ones included. |
| `Get-AzDoPipeline` | The pipeline definitions, each with the repository and path its YAML lives at. |
| `Get-AzDoPipelineYaml` | The YAML of a definition, or of a path in a repository, at a ref. |
| `Get-AzDoPipelineReference` | The references in one YAML document. Parsing only: no resolution, no network. |
| `Resolve-AzDoPipelineReference` | One reference, plus the file that made it and that file's aliases, to a repository and path -- or to an unresolved result with a reason. |
| `Get-AzDoPipelineDependencyGraph` | The whole graph: nodes and edges. |
| `Export-AzDoPipelineDependencyGraph` | The graph as JSON, DOT or HTML. |

Parsing and resolution are separate commands on purpose. Parsing is testable
against a file on disk with no credentials and no network; resolution needs to
know what exists in which repository. A combined command would report a
resolution failure as though it were a parsing result, and there would be no way
to tell which half was wrong.

## The two rules that make this hard

A template reference resolves by one of two rules, and which one applies depends
on whether an `@alias` is present:

```yaml
- template: templates/steps-build.yml            # relative to THIS FILE's directory
- template: templates/steps-build.yml@mainRepo   # from the ROOT of mainRepo
```

Those are different files whenever both exist. An implementation that anchors
both at the repository root, or both relative, produces a graph that is entirely
plausible and entirely wrong. `Resolve-AzDoPipelineReference` implements both,
and the tests pin the pair against each other.

A leading `/` anchors at the repository root even with no alias.

## What it does not do

Read-only, permanently:

- **Never queues, runs or triggers a pipeline.** Not behind a switch, not in a test.
- **Never writes to Azure DevOps.** Nothing is created, updated or deleted.

The HTTP method is not a parameter of the REST helper -- it is `Get`, always, and
no caller can ask for anything else. No exported command's name begins with a
writing verb, and a test asserts both.

## Credentials

A personal access token in `$env:AZDO_PAT`, and nothing else. Not a file, not a
parameter on any command. A PAT passed as a parameter ends up in `PSReadLine`
history, in `Start-Transcript` output and in script-block logging, and it is a
bearer credential for a whole organisation.

If the variable is absent, commands fail with a message naming it. They do not
prompt and do not fall back to anything.

## Unresolved references are output, not errors

A reference that cannot be resolved becomes an edge of kind `unresolved`
carrying the reason: an undeclared alias, a file that is not there, a repository
in another project. A broken pipeline is exactly the one worth hearing about,
and dropping it would make it indistinguishable from a clean one.

## Building

```powershell
./build.ps1              # clean, build, analyze, test
./build.ps1 -Task Test
```

Output goes to `output/`, test results to `testResults/`. Tests need neither a
token nor a network: the parser, the resolver and the exporters are all covered
offline.

## Layout

```
src/PSAzureDevOpsGraph/
  PSAzureDevOpsGraph.psd1     manifest, explicit FunctionsToExport
  PSAzureDevOpsGraph.psm1     dot-sources Private then Public
  Private/                    YAML parser, path arithmetic, REST client
  Public/                     the seven commands, one per file
tests/                        Pester 5+
build.ps1
```

## Notes on the YAML parser

The module parses the subset of YAML that pipeline files use rather than taking
a dependency on a YAML library, so it imports with nothing installed.

Block scalars are consumed as opaque text and never scanned. This matters:

```yaml
- script: |
    echo "template: not-a-reference.yml"
```

A regex over the raw file reports that line as a template reference and invents
an edge. The parser does not, and a test pins it.
