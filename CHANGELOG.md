# Changelog

All notable changes to PSAzureDevOpsGraph.

## 0.1.0

First iteration. The module reads a project's pipeline definitions, parses every
reference in the YAML behind them, resolves each to a repository and a path, and
emits the graph as JSON, DOT or a self-contained HTML page.

### Added

- `Get-AzDoRepository`, `Get-AzDoPipeline`, `Get-AzDoPipelineYaml` — the
  read-only REST layer, PAT from `$env:AZDO_PAT` only.
- `Get-AzDoPipelineReference` — structural extraction of the five reference
  kinds from one document, with no network and no credentials.
- `Resolve-AzDoPipelineReference` — the two resolution rules, and unresolved
  results carrying `file-not-found` or `alias-not-declared`.
- `Get-AzDoPipelineDependencyGraph` — cycle-safe assembly with node identity
  keyed by the thing rather than by traversal position.
- `Export-AzDoPipelineDependencyGraph` — JSON against `graph.schema.json`, DOT,
  and self-contained HTML.
- A `PreTag` gate with tests in it, asserting the read-only constraint
  structurally.
