# Articles

### Start here

Build a new store from related tables with a data-dict contract.

- [Get started with
  graft](https://jameshwade.github.io/graft/articles/getting-started.md):

  Turn three ordinary tables into reviewed, connected, versioned
  knowledge in an empty local store.

- [Use a data-dict contract with
  graft](https://jameshwade.github.io/graft/articles/data-dict-schema.md):

  Start from related tables, resolve their data dictionary, and
  understand exactly which rules graft enforces.

### Use graft

Review and accept changes, retrieve current and historical records, and
give agents bounded access to both.

- [Govern knowledge
  changes](https://jameshwade.github.io/graft/articles/knowledge-change-control.md):

  Review candidate changes, commit them atomically, and recover the
  accepted history of a record from one authoritative revision ledger.

- [Retrieve accepted
  knowledge](https://jameshwade.github.io/graft/articles/retrieval.md):

  Pin accepted state, get records, search public fields, and inspect the
  accepted revision history behind each answer.

- [Work with
  agents](https://jameshwade.github.io/graft/articles/agents.md):

  Give an agent bounded reads, a pinned accepted boundary, and a
  proposal path that still passes through validation, provenance, and
  review.

- [Supported
  integrations](https://jameshwade.github.io/graft/articles/compatibility.md):

  Choose supported ellmer, data-dict, and Commons versions and reproduce
  the checks behind Graft’s integration contracts.

### Add richer representations

Add semantic graph relationships with LinkML or synchronize a readable
working tree.

- [Add graph semantics with
  LinkML](https://jameshwade.github.io/graft/articles/linkml-schema.md):

  Use LinkML when a table contract needs ontology identifiers,
  inheritance, or semantic statements that produce a bounded graph
  projection.

- [Work with open
  knowledge](https://jameshwade.github.io/graft/articles/open-knowledge-format.md):

  Synchronize a readable OKF working tree, inspect its state, and review
  edits through Graft’s ordinary plan and commit contract.

### Design and internals

Understand storage and projection boundaries, contract compilation, and
the choices behind the v0.1 package design.

- [How graft stores and retrieves
  knowledge](https://jameshwade.github.io/graft/articles/architecture.md):

  See how source contracts, reviewable plans, accepted revisions, and
  derived read views fit together.

- [Contract compiler
  details](https://jameshwade.github.io/graft/articles/contract-compilers.md):

  Reproduce data-dict and LinkML builds and understand their validation,
  provenance, redaction, and digest boundaries.

- [The v0.1
  design](https://jameshwade.github.io/graft/articles/v01-design.md):

  Understand the deliberate pre-production cutover to a revision-first
  API, one commit path, selective S7 objects, and a smaller package
  scope.
