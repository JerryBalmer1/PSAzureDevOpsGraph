# PSAzureDevOpsGraph

Works out which Azure DevOps pipelines depend on what, so that *if I change this
template, which pipelines break?* has an answer.

## Status

Built in one iteration against the brief in
[docs/plans/0001-pipeline-dependency-graph.md](docs/plans/0001-pipeline-dependency-graph.md),
which also preserves the original request this repository was seeded with.

What is measured, and against what:

- **Unit tests** run against the built module with a synthetic project served
  from a mock. They cover the parser, both resolution rules, graph assembly
  (orphans, cycles, shared templates, unresolved references) and the three
  export formats.
- **One live project** has been read end to end: `jlbalmerjr1/ClaudeTesting` —
  15 pipeline definitions across 5 repositories, producing 48 nodes and 51
  edges, of which 2 are unresolved. The output is committed under
  [artifacts/](artifacts/) as JSON, DOT and HTML, and validates against
  `graph.schema.json`. Everything below about real-world behaviour comes from
  that one project.

What is **not** measured: no second organisation, no project large enough to
page, no non-default branch beyond a single `-Ref` round trip, and no classic
(non-YAML) definition outside the mock.

## Prerequisites

- PowerShell 7.2 or later.
- [powershell-yaml](https://github.com/cloudbase/powershell-yaml) 0.4.7 or
  later. This is a **runtime** dependency: the module parses YAML with it, and
  it is declared in the manifest's `RequiredModules`.
- To build: InvokeBuild 5.10.0+, Pester 6.1.0 (pinned), PSScriptAnalyzer
  1.21.0+, all pinned in [Requirements.psd1](Requirements.psd1).

## A worked example

```powershell
$env:AZDO_PAT = '<token with Code (Read) and Build (Read)>'

$graph = Get-AzDoPipelineDependencyGraph -Organisation jlbalmerjr1 -Project ClaudeTesting

$graph.edges | Where-Object kind -eq 'unresolved' |
    Select-Object from, ref, reason
```

Real output from the project named above, not an illustration:

```
from                                  ref                             reason
----                                  ---                             ------
yaml:pipelines-main/pipelines/p09.yml steps/common.yml@ghostTemplates alias-not-declared
yaml:pipelines-main/pipelines/p09.yml templates/missing-steps.yml     file-not-found
```

Two broken references in one file, needing two different fixes: the first
needs a `resources.repositories` entry for `ghostTemplates`, the second needs
the file.

Then write something to look at, or to diff:

```powershell
Export-AzDoPipelineDependencyGraph -Graph $graph -Format Html -Path ./graph.html
Export-AzDoPipelineDependencyGraph -Graph $graph -Format Json -Path ./graph.json
```

The HTML is self-contained and opens from a `file://` URL with no network.

## Command surface

| Command | Does |
|---|---|
| `Get-AzDoRepository` | The Git repositories in a project. Used to look files up, not to make nodes. |
| `Get-AzDoPipeline` | The pipeline definitions in a project, each with the repository and path its YAML lives at. |
| `Get-AzDoPipelineYaml` | The YAML of a definition, or of a path in a repository, at a given ref. |
| `Get-AzDoPipelineReference` | The references in one YAML document. Parsing only — no network, no credentials. |
| `Resolve-AzDoPipelineReference` | One reference to a repository and path, or an unresolved result carrying a reason. |
| `Get-AzDoPipelineDependencyGraph` | The graph: nodes and edges, against `graph.schema.json`. |
| `Export-AzDoPipelineDependencyGraph` | The graph as JSON, DOT or HTML. |

`Get-AzDoPipelineReference` and `Resolve-AzDoPipelineReference` are separate on
purpose. Parsing is testable against a file on disk with no credentials;
resolution needs to know what exists in which repository. A combined command
reports resolution failures as parsing results, with no way to tell which half
was wrong.

## Credentials

A personal access token in `$env:AZDO_PAT`, with **Code (Read)** and
**Build (Read)**. Nothing else is supported, and the alternatives are forbidden
rather than merely unimplemented:

- **Never a parameter.** No `-Pat`, no `-Token`, no `-Credential`. A value
  passed as a parameter reaches `PSReadLine` history, `Start-Transcript` output
  and the `ScriptBlock` logging event log.
- **Never a file.** No `~/.azdo`, no `-PatPath`, no fallback. `.gitignore`
  carries `*.pat` and `**/pat.txt` to make the mistake harder, not to support a
  path.
- **Never in a URL.** URLs are logged by proxies and captured in exception
  messages.

If the variable is absent, commands fail with a message naming it. They do not
prompt and do not continue anonymously.

## What it will not do

Read-only, permanently. It never queues, runs or triggers a pipeline; never
creates, updates or deletes anything; and no exported command is named with a
writing verb. There is no `-Force` that changes this. A `PreTag` test asserts
all three structurally against the AST rather than by searching the text.

## Running the tests

```powershell
./build.ps1                 # Clean, Lint, Build, Test
./build.ps1 -Task PreTag    # the seals on a finished iteration
```

`PreTag` is deliberately not in the default task, so a half-finished iteration
can still build green.

## Known limits

- **`resources.pipelines` across projects is untested.** The `source:` is
  matched against definitions in the project being graphed; a cross-project
  pipeline resource resolves to `pipeline-not-found`.
- **Refs are per-run, not per-repository.** `-Ref` applies to every file the
  walk reads. A `resources.repositories` entry that pins its own `ref:` is
  parsed but not honoured when fetching.
- **Template expressions are not evaluated.** A `template:` whose value is a
  runtime expression is recorded as written and will not resolve.
- **Paging is implemented but unexercised.** No fixture project is large enough
  to return a continuation token.

## Licence

MIT. See [LICENSE](LICENSE).
