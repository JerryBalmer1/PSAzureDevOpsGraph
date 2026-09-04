# Examples

One example, read from a real Azure DevOps project and committed whole: the
graph JSON the module produced, the HTML rendered from it, and a screenshot.

Run the command below **from the repository root**.

| Example | What it shows | Artifacts | Regenerate |
| --- | --- | --- | --- |
| **ClaudeTesting** | 15 pipelines, 30 YAML files and 4 repositories across one project — 51 nodes, 51 edges. Includes two unresolved template references and a four-node dependency cycle. | [html](claudetesting.html) · [graph json](input/claudetesting-graph.json) · [png](claudetesting.png) | `pwsh -NoProfile -File examples/Build-Examples.ps1` |

**Prerequisite for that command:** `$env:AZDO_PAT` must hold an Azure DevOps
personal access token with **Code (Read)** and **Build (Read)**. The token is
read from the environment variable by name and is never written to a file, an
argument or a URL. Nothing in this directory contains one.

No token, or no Azure DevOps account? Rebuild the HTML from the committed graph
instead — no network, same output:

```powershell
pwsh -NoProfile -File examples/Build-Examples.ps1 -Offline
```

## Everything here is read-only

The module issues `GET` requests and nothing else. **No pipeline is queued, run
or triggered** by generating this example, and nothing it does meters or bills.
The requests are sequential — there is no parallelism in the module at all — so
the fixture is read one call at a time.

## What the picture is actually showing

| | |
| --- | --- |
| **Blue** | pipeline definitions — 15 of them, seeded from the definition list rather than from edges, so `p10-orphan` appears despite referencing nothing and being referenced by nothing |
| **Teal** | YAML files, 30 of them, each one node however many pipelines include it |
| **Purple** | the 4 repositories the referenced files actually live in |
| **Orange** | two references that resolve to nothing — `@ghostTemplates/steps/common.yml` and `pipelines-main/.../missing-steps.yml` |

The sidebar's test-order panel calls out the four nodes in a **dependency
cycle**: `p08-cycle`, `pipelines/p08.yml`, `templates/cycle-a.yml` and
`templates/cycle-b.yml` have no valid order because each waits on another. The
traversal records both edges of a cycle and still terminates, which is why the
cycle is visible here rather than being an infinite loop or a missing edge.

## Two artifacts, two steps, deliberately separable

[`Build-Examples.ps1`](Build-Examples.ps1) does two things, and only the first
touches the network:

1. **Read** the project and write
   [`input/claudetesting-graph.json`](input/claudetesting-graph.json). This is
   the module's own output in its own schema, committed unedited.
2. **Map and render.** The graph is mapped onto PSGraphRenderToHtml's producer
   contract and rendered through PSGraphRender.

The mapping lives in the example, not in the module. PSAzureDevOpsGraph does
not depend on the render stack and this example did not make it start: it emits
its own shape, and anything that wants to draw it maps it.

### Unresolved references are carried, not dropped

The mapping's interesting case. Two of the 51 edges point at targets that are
not nodes — that is what makes them unresolved — and the producer contract
requires every edge endpoint to resolve. Carrying them means **inventing a node
for the missing target**, not discarding the edge.

The first version of this script discarded them, and rendered 49 edges from a
51-edge graph. A producer that silently drops what it could not resolve reports
a graph that looks complete and is not, and those two edges are the ones a
reader most wants to see.

## No machine paths, no token

`meta.roots` in the rendered document is the string `jlbalmerjr1/ClaudeTesting`
— an organisation and project, not a filesystem path. Nothing committed here
contains an absolute path or a credential.
