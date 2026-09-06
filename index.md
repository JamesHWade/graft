# graft

Durable knowledge for R workflows and agents

## Keep what you learn. Review what changes.

Give research conclusions, interpretations, definitions and related
records an accepted history. Start with `data-dict.yaml`, review
proposed changes, and let a later task return to the exact knowledge an
earlier task used.

[Build your first
store](https://jameshwade.github.io/graft/articles/getting-started.md)
[Try narrative
reuse](https://jameshwade.github.io/graft/articles/ecosystem.md)

## From a result to a reusable record

An R workflow produces a conclusion. A person corrects it. A later agent
needs the earlier answer and the evidence behind it. Replacing
yesterday’s file loses that distinction; Graft retains each accepted
revision and the producer recorded for the change.

| Describe | Review | Reuse |
|----|----|----|
| Use data-dict to describe fields, meaning and relationships. | Inspect a proposed plan, correct invalid references, then accept it. | Read current history or pin an exact boundary for a later task. |

data-dict supplies the contract. Graft adds validated acceptance, stable
identity, revisions, snapshots and bounded retrieval. Ordinary tables
are a useful starting point; their values can include Markdown,
interpretations, preferences and normalized evidence links.

Acceptance records a decision for a purpose. It does not make a claim
true, authorize access, or permit execution of stored code. Applications
retain those responsibilities.

## Start in R

Install the development package:

``` r

pak::pak("JamesHWade/graft")
```

The
[quickstart](https://jameshwade.github.io/graft/articles/getting-started.md)
runs entirely offline. It uses a shipped resolved data-dict contract to
create a store, reject a broken reference, accept a correction, inspect
history and pin a snapshot. No model credentials or Python installation
are required.

Author your own `data-dict.yaml` with the optional data-dict CLI, then
compile its resolved export in R. Existing compiled contracts also run
in R alone.
[LinkML](https://jameshwade.github.io/graft/articles/linkml-schema.md)
remains available for domains needing richer graph semantics.

## Choose your next workflow

### Review changing knowledge

Keep proposals separate from accepted records. Inspect changes, handle
stale plans and retry without manufacturing another revision.

[Review and accept
changes](https://jameshwade.github.io/graft/articles/knowledge-change-control.md)

### Return to an exact answer

Retain the full selected evidence across restarts and unchanged days.
Flag changed dependencies for review while preserving the earlier
interpretation.

[Retain an exact reuse
basis](https://jameshwade.github.io/graft/articles/reuse-basis.md)

### Give an agent bounded reads

Use ordinary ellmer tools with ellmer, Deputy or dsprrr. Keep
connections in the process that owns them and reconnect workers from
serializable references.

[Explore tested host
recipes](https://jameshwade.github.io/graft/articles/ecosystem.md)

### Calculate and inspect receipts

Evaluate accepted Definitions against a pinned boundary. Inspect the
recorded evidence path without treating a receipt as a fact-check.

[Calculate with accepted
Definitions](https://jameshwade.github.io/graft/reference/graft_calculate.md)

## What works together today

Graft’s tested host loops cover ellmer, Deputy and dsprrr; Commons
consumes a detached public copy and retains its own file measures.
Tempest owns research products and promotion; accepted-evidence restart
integration is tracked in
[\#50](https://github.com/JamesHWade/graft/issues/50). Rill’s Reader
integration, isolation and permanent Forget gates remain separate work.

The [integration
guide](https://jameshwade.github.io/graft/articles/compatibility.md)
records supported versions and limitations. The [ecosystem
guide](https://jameshwade.github.io/graft/articles/ecosystem.md)
separates tested composition from planned application behavior. Generic
read tools alone do not enforce Reader permissions or decide what an
agent may consult automatically.

## Read a result’s evidence path

Graft classifies recorded answer evidence as **Verified**, **Cited** or
**Untrusted**. Verified paths use governed calculations with matching
receipts; Cited paths use independently matched Graft reads. Failures,
unknown sources or mixed unsupported evidence keep a result Untrusted.

These labels describe the recorded path. They do not measure factual
accuracy, authenticate producer identities or guarantee that prose
faithfully represents a source. [Work with
agents](https://jameshwade.github.io/graft/articles/agents.md) explains
the checks and their limits.
