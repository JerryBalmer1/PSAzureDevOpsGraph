# PSAzureDevOpsGraph

Answers the question nobody can answer by reading a repository: **if I change
this template, which pipelines break?**

## Status

Built against one project (`jlbalmerjr1/ClaudeTesting`, four repositories,
fifteen pipeline definitions). Against that fixture it produces 48 nodes and 51
edges, resolves every reference that resolves, and reports the two that do not
with distinct reasons.

What that does **not** establish: it has been exercised against one project of
one shape. Pagination past a single page, classic (non-YAML) definitions, and
repositories in other projects are implemented but unexercised — see
[Known limits](#known-limits).

## Prerequisites

- PowerShell **7.2** or later.
- Runtime: `powershell-yaml` **0.4.7** or later. It is declared in the manifest's
  `RequiredModules`, so `Import-Module` fails on a machine without it rather than
  succeeding and failing later when a document is parsed.
- Build only, pinned in `./Requirements.psd1`: InvokeBuild 5.10.0+,
  Pester **6.1.0 exactly**, PSScriptAnalyzer 1.21.0+.

Pester is pinned rather than floored because Pester 5 and 6 disagree on
assertion syntax, discovery and mocking, and a bare `Invoke-Pester` picks one
silently.

## A worked example

```powershell
$env:AZDO_PAT = '<token with Code (Read) and Build (Read)>'

Import-Module ./output/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psd1

$graph = Get-AzDoPipelineDependencyGraph -Organisation jlbalmerjr1 -Project ClaudeTesting

$graph.nodes | Group-Object kind | Select-Object Name, Count
$graph.edges | Group-Object kind | Select-Object Name, Count
```

Real output from that project:

```
Name     Count          Name               Count
----     -----          ----               -----
pipeline    15          definition            15
repo         3          template              21
yaml        30          repositoryResource     8
                        pipelineResource       3
                        checkout               1
                        extends                1
                        unresolved             2
```

The two unresolved references, which are the answer the tool exists to give:

```powershell
$graph.edges | Where-Object kind -eq 'unresolved' | Format-Table from, ref, reason
```

```
from                                  ref                             reason
----                                  ---                             ------
yaml:pipelines-main/pipelines/p09.yml steps/common.yml@ghostTemplates alias-not-declared
yaml:pipelines-main/pipelines/p09.yml templates/missing-steps.yml     file-not-found
```

Parsing needs no credential and no network at all:

```powershell
Get-AzDoPipelineReference -Path ./azure-pipelines.yml
```

## Command surface

| Command | Returns |
|---|---|
| `Get-AzDoRepository` | The Git repositories in a project. |
| `Get-AzDoPipeline` | The pipeline definitions, each with the repository and path its YAML lives at. |
| `Get-AzDoPipelineYaml` | The YAML text of a definition, or of a path in a repository, at a given ref. |
| `Get-AzDoPipelineReference` | The references in one YAML document. Parsing only — no resolution, no network. |
| `Resolve-AzDoPipelineReference` | One reference to a repository and path, or an unresolved result with a reason. |
| `Get-AzDoPipelineDependencyGraph` | The graph: nodes and edges. |
| `Export-AzDoPipelineDependencyGraph` | The graph as JSON, DOT or HTML. |

Parsing and resolution are separate commands on purpose. Parsing is testable
against a file on disk with no credentials; resolution needs to know what exists
in which repository. A combined command would report resolution failures as
parsing results, with no way to tell which half was wrong.

## Credentials

A personal access token in `$env:AZDO_PAT`, with **Code (Read)** and
**Build (Read)** scope. Nothing else.

Not a parameter, not a file, not in a URL. A value passed as a parameter ends up
in `PSReadLine` history, in `Start-Transcript` output and in the ScriptBlock
logging event log, and the token is a bearer credential for an entire
organisation. When the variable is absent, commands fail naming it; they do not
prompt, search, or continue anonymously.

**Read-only, permanently.** It never queues, runs or triggers a pipeline, and
never creates, updates or deletes anything. No exported command is named with a
writing verb, and there is no `-Force` that changes it.

## Running the tests

```powershell
./build.ps1                       # Clean, Lint, Build, Test
./build.ps1 -Task PreTag          # the pre-tag seals, excluded from the default
```

The integration layer reads the live fixture and is tagged `Integration` and
`RequiresPat`. Without `$env:AZDO_PAT` it is skipped and says so — a layer that
reports success where nothing could contradict it is worse than one that admits
it did not run.

## Known limits

- **One project, one shape.** Every claim above is measured against
  `jlbalmerjr1/ClaudeTesting`. Nothing here is evidence about a project with
  hundreds of definitions.
- **Paging is implemented but unexercised.** The continuation-token loop in
  `Invoke-AzDoRestMethod` has never had a second page to fetch.
- **Cross-project references are not resolved.** `resources.repositories` with a
  `name:` of `OtherProject/repo` is reduced to its last segment and looked up in
  the current project. Within one project that is correct; across projects it
  would resolve to the wrong repository or to none.
- **`ref:` on a repository resource is ignored.** Files are read from each
  repository's default branch, so a `resources.repositories` entry pinned to a
  tag or another branch is resolved against `main` instead.
- **Classic (non-YAML) definitions** appear as pipeline nodes with no definition
  edge. Implemented, but the fixture contains none, so it is unexercised.
- **`Get-AzDoPipelineYaml -PipelineId`** is implemented and covered only
  indirectly; the graph uses the repository-and-path form.

## Licence

MIT. See `./LICENSE`.
