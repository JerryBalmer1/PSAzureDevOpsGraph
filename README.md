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
