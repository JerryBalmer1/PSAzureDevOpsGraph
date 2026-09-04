# HANDOFF

**Read this first.**

## State, as of pass 0043

**Where it is.** `v0.4.0`, tagged by this pass under decision 0006, with
[`docs/worklog/v0.4.0.md`](worklog/v0.4.0.md) beside it. The minor was taken
from this repository's `git tag` list and the harness LEDGER version line,
which agreed on `v0.3.0` as the frontier.

**What pass 0043 did here.** Documentation and generated artifacts only. **No
`src/` file changed.** `examples/` holds the ClaudeTesting fixture as the
module reads it — 51 nodes, 51 edges — as committed graph JSON, rendered HTML
and a 1600x900 screenshot that is now the README's hero image. Generating it
issued `GET` requests only; no pipeline was queued, run or triggered.

**The mapping is in the example, not in the module.** This module emits its own
graph shape and does not depend on the render stack. `examples/Build-Examples.ps1`
maps that shape onto PSGraphRenderToHtml's producer contract, and the dependency
still points one way.

**Known drift, recorded not repaired.**
`src/PSAzureDevOpsGraph/PSAzureDevOpsGraph.psd1` declares
`ModuleVersion = '0.1.0'` while the tag line has reached `v0.4.0`. The two have
been diverging since the tag line started moving on docs-only minors, and
nothing compares them: the `PreTag` task filters on a `PreTag` Pester tag that
no test in `tests/` carries, so `./build.ps1 -Task PreTag` currently runs zero
tests and passes. Both facts predate this pass and neither was touched by it —
a pass that changes `src/` is the right place to decide whether the manifest
should track the tag, and whether a gate that asserts nothing should exist.

**Next.** Nothing here is blocked. The two drift items above want a decision
before code moves.

## What this is

Reads an Azure DevOps project through the REST API and returns the whole
pipeline dependency graph as data: the pipeline definitions, the YAML files they
reference, the repositories those files live in, and the edges between them —
including the references it could **not** resolve, which are the ones worth
hearing about.

Seven exported commands:

| Command | Does |
| --- | --- |
| `Get-AzDoRepository` | the Git repositories in a project |
| `Get-AzDoPipeline` | the pipeline definitions, each with the repository and path its YAML lives at |
| `Get-AzDoPipelineYaml` | the YAML text at a path, or `$null` if absent |
| `Get-AzDoPipelineReference` | the references in one document. Parsing only — no resolution, no network |
| `Resolve-AzDoPipelineReference` | one reference to a repository and path, or an unresolved result with a reason |
| `Get-AzDoPipelineDependencyGraph` | the graph: nodes and edges |
| `Export-AzDoPipelineDependencyGraph` | the graph as JSON, DOT or HTML |

`./build.ps1` is the only entry point. It runs `Clean, Lint, Build, Test`.

## Boundaries

- **Read-only, permanently.** Every REST call is a `GET`. The module never
  queues, runs or triggers a pipeline and never creates, updates or deletes
  anything. There is no `-Force` that changes this and no command whose name
  begins with a writing verb — a test in `tests/` asserts that by enumerating
  the exported surface.
- **The PAT comes from `$env:AZDO_PAT` and nowhere else.** Not a parameter, not
  a file path, never placed in a URL. A value passed as a parameter ends up in
  `PSReadLine` history, in `Start-Transcript` output and in the ScriptBlock
  logging event log, and a PAT is a bearer credential for an entire
  organisation. Absent, commands fail naming the variable; they do not prompt
  and do not fall back.
- **Parsing and resolution are separate commands on purpose.** Parsing is
  testable against a file on disk with no credentials and no network;
  resolution needs to know what exists in which repository. A combined command
  reports resolution failures as parsing results, with no way to tell which
  half was wrong.
- **An unresolved reference is carried, never dropped**, with a reason. A
  broken pipeline that vanishes from the output looks identical to a clean one.
  The two reason codes stay distinct because they need different fixes: a
  missing file is not a missing `resources.repositories` entry.
- **The current repository is a property of the file, not of the traversal.** A
  relative reference inside a cross-repository template stays in that
  template's repository. This is the rule a resolver that joins every reference
  to the repository root gets wrong without erroring.
- **The exported HTML is self-contained.** No external script, stylesheet,
  `@import` or `http(s)` reference of any kind, so it opens from a `file://`
  URL with no network.

## Two lines, and they are never compared

This repository is governed from the
[AI.Agent.Claude.PowerShellModuleBuilder](https://github.com/JerryBalmer1/AI.Agent.Claude.PowerShellModuleBuilder)
harness, which built it in order to measure how much an agent plugin helps
build a module. Two distinct lines run through the same remote:

- **The deliverable line** — `main` and its `v0.<minor>.0` tags. This is the
  module. Under
  [decision 0006](https://github.com/JerryBalmer1/AI.Agent.Claude.PowerShellModuleBuilder/blob/main/decisions/0006-target-versioning-and-tags.md),
  the module files persist rather than being wiped between plans, every plan
  that touches this repository ends with one annotated `v0.<minor>.0` tag whose
  message carries the three scores, and each such plan writes
  `docs/worklog/v0.<minor>.0.md` beside it so every tag carries its reasoning.
  The operator's assistant assigns the minor number in the pass prompt; the
  agent never invents one.
- **The measurement line** — the `run-*` branches. Each is produced by
  `Reset-Target.ps1`, which materialises a four-file seed into a fresh `git
  init`, so every run branch is an **orphan root** and that property is
  load-bearing: it is what marks a measurement branch as structurally distinct.
  Measurement branches are never merged to `main` and never tagged.

**Do not read a run branch as a release, and do not compare a run's scores with
a tag's.** The scores in `README.md` are the harness's, each linked to the run
record that produced it.

## How `main` and tags move

Under
[decision 0008](https://github.com/JerryBalmer1/AI.Agent.Claude.PowerShellModuleBuilder/blob/main/decisions/0008-target-main-follows-tags.md)
and
[decision 0009](https://github.com/JerryBalmer1/AI.Agent.Claude.PowerShellModuleBuilder/blob/main/decisions/0009-agent-moves-both-mains.md):

- Work happens on a `pass-NNNN-*` branch.
- The pass pushes the branch and the annotated tag the prompt names.
- `main` is then fast-forwarded to the newest tag and pushed, with ancestry
  verified by `git merge-base --is-ancestor` before every push.
- **Fast-forward only.** A non-fast-forward is a hard stop and a finding, never
  forced. History is never rewritten. `Publish-Module` and all other
  publication remain the operator's.

`main` descends from two roots. GitHub's initial commit and run 002's orphan
root had no common ancestor, so `v0.1.0` could not fast-forward anything; the
operator chose one `--allow-unrelated-histories` merge, performed once, and both
roots are preserved. That is what `v0.2.0` marks, and it is why the rule above
is satisfiable from here on. See `docs/worklog/v0.2.0.md`.

## Version ledger

| Version | What it marks |
| --- | --- |
| `v0.1.0` | run 002's build — the module itself. Tagged retroactively onto `79e02fb`, because decision 0006 predated the pass but did not reach its prompt |
| `v0.2.0` | the history unification: one merge joining GitHub's initial commit and run 002's orphan root, so `main` can follow tags by fast-forward. No source, test or build file changed |
| `v0.3.0` | documentation only. The measurement history — the ladder, the control, and the bounds each number carries — reaches the repository it measured. **Module code is byte-identical to `v0.2.0`**; the worklog asserts it with a diff |

**No version of this module has been published to the PowerShell Gallery.**

Runtime dependency: `powershell-yaml`. Requires PowerShell 7.2 or later.

## Open

- **Never run against a real project.** Every score describes one 15-pipeline
  fixture with a hand-written oracle. There is no paging test against a project
  large enough to page, and performance is unmeasured beyond *13.4 seconds for
  30 files*.
- **`azdo-graph-assembly` states the repository-node rule too narrowly**, in
  the harness plugin this module is built by. Every plugin-on run that follows
  it exactly is missing one node — `repo:consumer-app` — and that is the single
  defect among the ladder's 26 first-shot differences. It is a finding against
  the plugin, not against this module's shipped code, which fixed it.
- **Two output conventions were guessed wrong by four independent blind
  sessions in the same direction**: `alias` written on edges where the oracle
  omits it, and `reason` written as a bare token rather than
  `code: explanation`. The plugin states neither. Shipped code is correct; the
  observation is about what the plugin does not say.
- **The fixture names its own cases.** The `ClaudeTesting` YAML carries comments
  identifying each case. Every run has read them by design and always will, the
  fixture being frozen. It is a permanent bound on every number in `README.md`,
  and it is disclosed rather than repaired.
- **Next: nothing is scheduled.** The AzDO run ladder is complete at 004–006
  and its control complete at 007. The next measurement the harness names as
  worth taking is per-skill ablation — which of the fourteen skills carries the
  19/33 → 33/33 — not another run of this shape. That is the harness's decision
  and not this repository's.

## Where the reasoning lives

| File | Read it when |
| --- | --- |
| `README.md` | what the module does, and every score with the artifact behind it |
| `docs/worklog/` | why a tag did what it did |
| the harness's `runs/` | the graphs, diffs, conformance results and findings themselves |
