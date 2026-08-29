# PSAzureDevOpsGraph

Works out which Azure DevOps pipelines depend on what.

## The question it answers

Azure DevOps pipeline YAML composes by reference. A pipeline pulls in templates,
templates pull in other templates, and those references cross repository
boundaries — so the thing you most want to know is not visible from any one
file:

> **If I change this template, which pipelines break?**

`PSAzureDevOpsGraph` reads a project through the REST API and returns the whole
dependency graph as data: the pipelines, the YAML files they reference, the
repositories those files live in, and the edges between them — including the
references it could **not** resolve, which are the ones worth hearing about.

## Read-only, permanently

The module never queues, runs, or triggers a pipeline, and never creates,
updates, or deletes anything in Azure DevOps. Every REST call it makes is a
`GET`. There is no `-Force` that changes this and no command whose name begins
with a writing verb — a test in `tests/` asserts that, by enumerating the
exported surface.

## Credentials

A personal access token, read from `$env:AZDO_PAT`, and nothing else.

Not a parameter, not a file path, never placed in a URL. A value passed as a
parameter ends up in `PSReadLine` history, in `Start-Transcript` output, and in
the ScriptBlock logging event log — and a PAT is a bearer credential for an
entire organisation. If the variable is absent, commands fail with a message
naming it; they do not prompt and do not fall back to anything.

The token needs **Code (Read)** and **Build (Read)**.

```powershell
$env:AZDO_PAT = '<paste your token here, in your own shell>'
```

## Install

This branch is a run artifact, not a gallery release. Clone and import:

```powershell
git clone --branch run-002-first-build https://github.com/JerryBalmer1/PSAzureDevOpsGraph.git
cd PSAzureDevOpsGraph
Install-Module powershell-yaml -Scope CurrentUser   # the one runtime dependency
./build.ps1                                          # Clean, Lint, Build, Test
Import-Module ./output/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psd1
```

Requires PowerShell 7.2 or later.

## Usage

All three examples below are real output from the fixture project used to
develop the module — 15 pipeline definitions across 4 repositories.

### 1. Get the whole graph

```powershell
$graph = Get-AzDoPipelineDependencyGraph -Organisation myorg -Project MyProject
$graph.nodes | Group-Object kind | Select-Object Count, Name
```

```
Count Name
----- ----
   15 pipeline
    4 repo
   30 yaml
```

51 edges: 21 `template`, 15 `definition`, 8 `repositoryResource`,
3 `pipelineResource`, 2 `unresolved`, 1 `extends`, 1 `checkout`.

### 2. Find the broken references

The point of the tool. A reference that cannot be resolved is reported with a
reason, never dropped — a broken pipeline that vanishes from the output looks
identical to a clean one.

```powershell
$graph.edges | Where-Object kind -eq 'unresolved' | Format-List from, ref, reason
```

```
from   : yaml:pipelines-main/pipelines/p09.yml
ref    : steps/common.yml@ghostTemplates
reason : alias-not-declared: 'ghostTemplates' is not in resources.repositories of
         pipelines/p09.yml, so the repository is unknown and the path cannot be
         resolved at all

from   : yaml:pipelines-main/pipelines/p09.yml
ref    : templates/missing-steps.yml
reason : file-not-found: resolved to pipelines/templates/missing-steps.yml in
         pipelines-main, which does not exist
```

The two reasons stay distinct because they need different fixes: one is a
missing file, the other a missing `resources.repositories` entry.

### 3. Answer the actual question

```powershell
$target = 'yaml:pipelines-main/pipelines/templates/steps-build.yml'
$graph.edges | Where-Object to -eq $target | Select-Object from, kind, ref
```

```
from                                  kind     ref
----                                  ----     ---
yaml:pipelines-main/pipelines/p01.yml template templates/steps-build.yml
```

Note what this does **not** match. `pipelines-main` also holds
`templates/steps-build.yml` at its root, and a cross-repository reference
`templates/steps-build.yml@mainPipelines` resolves there instead. Same text,
two rules, two files — a resolver that joins every reference to the repository
root returns the wrong one without erroring.

### Export it

```powershell
$graph | Export-AzDoPipelineDependencyGraph -Path ./graph.json              # JSON
$graph | Export-AzDoPipelineDependencyGraph -Path ./graph.dot  -Format Dot  # Graphviz
$graph | Export-AzDoPipelineDependencyGraph -Path ./graph.html -Format Html # standalone page
```

The HTML is self-contained: no external script, stylesheet, `@import`, or
`http(s)` reference of any kind, so it opens from a `file://` URL with no
network.

## Commands

| Command | Does |
|---|---|
| `Get-AzDoRepository` | The Git repositories in a project. |
| `Get-AzDoPipeline` | The pipeline definitions, each with the repository and path its YAML lives at. |
| `Get-AzDoPipelineYaml` | The YAML text at a path, or `$null` if absent. |
| `Get-AzDoPipelineReference` | The references in one document. Parsing only — no resolution, no network. |
| `Resolve-AzDoPipelineReference` | One reference to a repository and path, or an unresolved result with a reason. |
| `Get-AzDoPipelineDependencyGraph` | The graph: nodes and edges. |
| `Export-AzDoPipelineDependencyGraph` | The graph as JSON, DOT or HTML. |

Parsing and resolution are separate commands on purpose. Parsing is testable
against a file on disk with no credentials and no network; resolution needs to
know what exists in which repository. A combined command reports resolution
failures as parsing results, with no way to tell which half was wrong.

## How references resolve

| Reference | Resolves |
|---|---|
| `templates/x.yml` | relative to the **directory of the file** making the reference |
| `templates/x.yml@alias` | from the **root** of the repository `alias` names |

The alias is looked up in the `resources.repositories` of the file making the
reference, and the current repository is a property of the file rather than of
the traversal — so a relative reference inside a cross-repository template stays
in that template's repository.

`checkout: self` produces nothing. `checkout: <alias>` is a dependency on that
repository and never a template reference. `extends.template` is its own edge
kind. A parameter named `buildTemplate` is not a reference, however much its
value looks like a path.

## Status

Built in one session as run 002 of the harness at
[AI.Agent.Claude.PowerShellModuleBuilder](https://github.com/JerryBalmer1/AI.Agent.Claude.PowerShellModuleBuilder).
Measured, on that harness:

| Gate | Result |
|---|---|
| Build | exit 0 — analyzer clean, 37/37 tests, 82.88% coverage against a 40% target |
| Conformance (shape) | 57/57 cases across 33 assertions |
| Functional (behaviour) | 12/12 cases — the produced graph equals the hand-written oracle exactly |

**What that does and does not mean.** The functional score says the graph
matches a hand-written oracle for one 15-pipeline fixture. It has never been run
against a real project of any size, there is no paging test against a project
large enough to page, and performance is unmeasured beyond "13 seconds for 30
files". Known gaps are recorded in the run's
[findings](https://github.com/JerryBalmer1/AI.Agent.Claude.PowerShellModuleBuilder/blob/main/runs/002-first-build/findings.md).

Not published to the PowerShell Gallery. This is a branch, not a release.

## Licence

MIT. See [LICENSE](LICENSE).
