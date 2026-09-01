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
Import-Module ./output/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psd1

$env:AZDO_PAT = '<a token with Code (Read) and Build (Read))>'
$graph = Get-AzDoPipelineDependencyGraph -Organisation contoso -Project platform

$graph | Export-AzDoPipelineDependencyGraph -Path ./graph.json
$graph | Export-AzDoPipelineDependencyGraph -Path ./graph.html -Format Html
```

The HTML is self-contained and opens from a `file://` URL with no network.

### What it can tell you

Which pipelines would break if one file changed:

```powershell
$graph.edges | Where-Object to -eq 'yaml:pipelines-main/templates/steps-build.yml'
```

And the references it could not resolve, which is the half a reference-derived
graph usually loses:

```powershell
$graph.edges | Where-Object kind -eq 'unresolved' |
    Select-Object from, ref, refKind, reason
```

`reason` is `file-not-found` (the path resolved but no such file exists — add
the file) or `alias-not-declared` (an `@alias` with no `resources.repositories`
entry — add the entry). They are kept apart because they need different fixes.

## Commands

| Command | Does |
|---|---|
| `Get-AzDoRepository` | The Git repositories in a project. |
| `Get-AzDoPipeline` | The pipeline definitions, each with the repository and path its YAML lives at. |
| `Get-AzDoPipelineYaml` | The YAML text of a definition, or of a path in a repository, at a given ref. |
| `Get-AzDoPipelineReference` | The references in one YAML document. Parsing only — no resolution, no network. |
| `Resolve-AzDoPipelineReference` | One reference to a repository and path, or to an unresolved result carrying a reason. |
| `Get-AzDoPipelineDependencyGraph` | The graph: nodes and edges. |
| `Export-AzDoPipelineDependencyGraph` | The graph as JSON, DOT or HTML. |

Parsing and resolution are separate commands on purpose. Parsing is testable
against a file on disk with no credentials and no network; resolution needs to
know what exists in which repository. A combined command reports resolution
failures as parsing results, with no way to tell which half was wrong.

## The two resolution rules

They produce different files from the same reference text, which is the single
most consequential thing this module gets right or wrong.

**No `@alias`** — relative to the directory of the *file making the reference*:

```
file  repos/pipelines-main/pipelines/p01.yml
ref   templates/steps-build.yml
->    repos/pipelines-main/pipelines/templates/steps-build.yml
```

**With `@alias`** — from the *root of the aliased repository*:

```
file  repos/consumer-app/azure-pipelines.yml
ref   templates/steps-build.yml@mainPipelines
->    repos/pipelines-main/templates/steps-build.yml
```

A repository can hold both of those files. A root-relative resolver does not
error — it returns the wrong one, confidently.

## Credentials

The PAT comes from `$env:AZDO_PAT` and from nowhere else. It is never a
parameter, never read from a file, and never placed in a URL: a value passed as
a parameter ends up in `PSReadLine` history, in `Start-Transcript` output and in
the `ScriptBlock` logging event log, and a PAT is a bearer credential for an
entire organisation.

When the variable is absent, commands fail with a message naming it. They do not
prompt, do not search, and do not fall back to anonymous access.

## Read-only, permanently

It never queues, runs or triggers a pipeline; never creates, updates or deletes
anything in Azure DevOps; and has no command whose name begins with a writing
verb. `Export-AzDoPipelineDependencyGraph` writes a local file and nothing else.
There is no `-Force` that changes any of this.

A tool that walks an organisation's pipelines is exactly the kind of thing that
gets run with a high-privilege token. That is the reason for the constraint
rather than an exception to it.

## Building

```powershell
./build.ps1
```

`Clean`, `Lint`, `Build`, `Test`. Lint is a gate rather than a report, and the
`Test` task fails the build when line coverage falls below its declared target.
`PreTag` is a separate task, deliberately not in the default, so a half-finished
iteration can still build green.

| Path | What |
|---|---|
| `build.ps1` | Entrypoint. Resolves the pins in `Requirements.psd1`, then hands off to InvokeBuild. |
| `PSAzureDevOpsGraph.build.ps1` | The tasks. |
| `src/PSAzureDevOpsGraph/Public` | One exported function per file, named for the file. |
| `src/PSAzureDevOpsGraph/Private` | Helpers, nested by subsystem: `Rest`, `Yaml`, `Graph`. |
| `tests/` | Pester 6. `tests/PreTag.Tests.ps1` holds the pre-tag seals. |

Build dependencies are pinned in `Requirements.psd1` and resolved rather than
installed. The one runtime dependency, `powershell-yaml`, is declared in the
manifest.
