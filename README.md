# PSAzureDevOpsGraph

A PowerShell module that works out which Azure DevOps pipelines depend on what,
so that *if I change this template, which pipelines break?* has an answer.

Read-only, always. It never queues, runs, creates, updates or deletes anything.

## Install

```powershell
git clone https://github.com/JerryBalmer1/PSAzureDevOpsGraph.git
Import-Module ./PSAzureDevOpsGraph/src/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psd1
```

Requires PowerShell 7.2 or later. No other modules at runtime; Pester 5+ to run
the tests.

## Credentials

The module reads a personal access token from `$env:AZDO_PAT` and from nowhere
else.

```powershell
$env:AZDO_PAT = Read-Host -AsSecureString | ConvertFrom-SecureString -AsPlainText
```

There is no `-Pat` parameter, no file fallback and no prompt. A PAT passed as a
parameter value is captured by `PSReadLine` history, by `Start-Transcript` and
by ScriptBlock logging, and it is a bearer credential for an entire
organisation. If the variable is absent, commands fail with a message naming it.

The token needs **Code (read)** and **Build (read)**. Nothing else.

## Use

```powershell
$graph = Get-AzDoPipelineDependencyGraph -Organisation contoso -Project payments

# The diffable form.
$graph | Export-AzDoPipelineDependencyGraph -Format Json -Path graph.json

# The readable form: one self-contained file, no CDN.
$graph | Export-AzDoPipelineDependencyGraph -Format Html -Path graph.html

# What could not be resolved.
$graph.edges | Where-Object kind -eq 'unresolved' |
    Format-Table from, ref, reason
```

Which pipelines break if a template changes:

```powershell
$target = 'yaml:templates-shared/steps/common.yml'
$graph.edges | Where-Object to -eq $target | ForEach-Object from
```

## Commands

| Command | Does |
|---|---|
| `Get-AzDoRepository` | The Git repositories in a project, including empty ones. |
| `Get-AzDoPipeline` | The pipeline definitions, each with the repository and path its YAML lives at. |
| `Get-AzDoPipelineYaml` | The YAML text of a definition, or of a path in a repository, at a ref. |
| `Get-AzDoPipelineReference` | The references in one YAML document. Parsing only — no resolution, no network. |
| `Resolve-AzDoPipelineReference` | One reference, plus its file and that file's aliases, to a repository and path — or to an unresolved result with a reason. |
| `Get-AzDoPipelineDependencyGraph` | The whole graph: nodes and edges. |
| `Export-AzDoPipelineDependencyGraph` | JSON, DOT or HTML. |

Parsing and resolution are separate commands on purpose. Parsing is testable
against a file on disk with no credentials and no network; resolution needs to
know what exists in which repository. Combined, a resolution failure would be
reported as though it were a parsing result, with no way to tell which half was
wrong.

## How references resolve

Azure Pipelines uses two different rules, chosen by whether an `@alias` is
present. Getting them the wrong way round usually does not raise an error — it
silently picks a *different file that also exists*.

| Written | Resolved |
|---|---|
| `template: templates/build.yml` | Relative to the **directory of the referring file**, in its own repository. |
| `template: templates/build.yml@shared` | From the **root** of the repository the alias `shared` names. |

Aliases are declared per file by `resources.repositories` and do not cross
files. An `@alias` that the file never declared is not a guess — it is an
unresolved edge with the reason `alias-not-declared`.

## The graph

`version`, `organisation`, `project`, `generatedBy`, `nodes`, `edges`.

Nodes are `pipeline`, `yaml` or `repo`. Ids are `pipeline:<name>`,
`yaml:<repo>/<path>` and `repo:<name>`.

Edges are `definition` (a pipeline to the YAML it is registered against),
`template`, `extends`, `pipelineResource`, `repositoryResource`, `checkout`, and
`unresolved`.

Four things the walk does deliberately:

- **A repository is a node when it takes part** — when it holds one of the YAML
  files, or when something references it. A repository that holds no pipeline
  YAML and that nothing points at is not a dependency of anything, and adding it
  would put a node in the graph with no path to any pipeline. Use
  `Get-AzDoRepository` for the inventory; that command does list empty ones.
- **`checkout: self` is not an edge.** It is the repository the file is already
  in — a build instruction, not a dependency the file would not otherwise have.
  `checkout: <alias>` is an edge, because it pulls in a second repository.
- **A reference that cannot be resolved becomes an `unresolved` edge carrying a
  reason** — never a dropped edge. A broken pipeline that vanishes from the
  output looks exactly like a clean one, which is the opposite of useful. The
  edge still points at the place the file should have been, so it can be acted
  on; where even the repository is unknown, the target names the alias
  (`yaml:@ghostTemplates/steps/common.yml`).
- **The walk is cycle-safe.** A template cycle is a thing real projects contain.
  It is reported, not treated as an error.

`alias` on an edge records where an alias is *declared* — the `repository:` key
of a repository resource, the `pipeline:` key of a pipeline resource. It is not
repeated on edges that merely use one; the use is already in `ref`.

## Build

```powershell
./build.ps1            # clean, stage to output/, run tests
./build.ps1 -Task Test
```

The test suite needs no credentials and makes no network calls.

## Licence

MIT. See [LICENSE](LICENSE).
