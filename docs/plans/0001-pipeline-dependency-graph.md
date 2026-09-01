# 0001 — A pipeline dependency graph for Azure DevOps

## The request, as it arrived

The repository was seeded with a README stating what the author wanted. It is
preserved here verbatim, because the README at the root is now the module's own
and the original is the only record of what was asked for.

---

# PSAzureDevOpsGraph

A PowerShell module for working out which Azure DevOps pipelines depend on what.

## The problem

Azure DevOps pipeline YAML composes by reference. A pipeline pulls in templates,
templates pull in other templates, and those references cross repository
boundaries. None of it is visible from any one file.

So the question nobody here can answer is: **if I change this template, which
pipelines break?** We have templates nobody will touch because no one can say
what depends on them, and pipelines nobody can account for.

I want to be able to point a command at a project and get the whole dependency
graph out — pipelines, the YAML files they reference, the repositories those
files live in, and the edges between them.

## What I want it to do

- Read a project and produce the graph, as data rather than as a picture.
- Export it as something I can look at, and as something I can diff.
- Tell me about references it could not resolve, rather than quietly dropping
  them. A broken pipeline is exactly the one I want to hear about, and if it
  vanishes from the output it looks identical to a clean one.

## Constraints I already know about

- **Read-only.** It never queues, runs, or modifies anything. This is a tool for
  answering a question about a project, not for changing one.
- **Credentials come from the environment.** A personal access token in
  `$env:AZDO_PAT`, not a parameter and not a file. It is a bearer credential for
  a whole organisation, and anything passed as a parameter ends up in shell
  history and in transcripts.

## Status

Nothing built yet. This file is what I want; the rest is not written.

---

## Definition of done, decided before the work

How this would be tested was settled before any code was written:

1. `./build.ps1` exits 0 with zero analyzer findings, Pester green, and line
   coverage at or above the declared target of 70% measured against the built
   psm1.
2. `Get-AzDoPipelineDependencyGraph` runs against a live project and produces a
   graph that validates against `graph.schema.json`.
3. Every reference kind in the brief has a test that would fail if the kind were
   collapsed into another: `extends` distinct from `template`, `checkout: self`
   producing nothing, `resources.pipelines` targeting a definition rather than a
   file.
4. Both resolution rules have a test whose expected path differs from what the
   other rule would produce, so a resolver that implements only one is red
   rather than plausible.
5. An unresolved reference appears in the output with a reason, and the two
   reasons are asserted to be different from each other.
6. A cycle terminates, and both of its edges are present.
7. An orphan pipeline is present; a repository nothing references is absent.

## The surface, decided before the work

The seven commands in the brief, unchanged. Two helpers had no home in that
table and went to `Private/`: a path normaliser and the cached file fetch.
Putting either in `Public/` would have broken the three-way agreement between
`Public/*.ps1` basenames, `FunctionsToExport`, and the generated export call.

## What was deliberately not built

- No caching between runs. The cache lives for one graph call.
- No parallel fetching. One project's worth of definitions and templates
  completes well inside the time budget sequentially, and concurrency here would
  buy speed at the cost of a retry story that nothing yet needs.
- No `-WhatIf` anywhere. There is nothing to preview; the module writes nothing.
