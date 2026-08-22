# Measures: governed calculations as reviewed knowledge

Date: 2026-08-22
Status: approved design, phase 1 of 3

## Motivation

[posit-dev/commons](https://github.com/posit-dev/commons) demonstrates a
"semantic layer" for data agents: governed calculations (measures) that a
model invokes by name instead of writing SQL or R, plus deterministic trust
tagging of answers derived from them. Commons governs calculations over
external data sources; graft can close the loop. Agents both consume accepted
knowledge through measures and propose new measures that enter through the
same plan → review → commit gate as any other record.

The agreed direction is a layered design delivered in three phases:

1. **Declarative measures in the store** (this spec).
2. **Receipts + classifier**: widen all tool receipts with commit/snapshot
   ids and add a `graft_verify()` that classifies an ellmer tool trace into
   Verified/Cited/Untrusted. Separate spec.
3. **R-function measure layer and commons interop**: commons-compatible
   file-based measures and an adapter exposing a store/snapshot as a commons
   `data_source`. Separate spec.

This document specifies phase 1 only.

## Data model: measures are records

A reserved system class, `graft:measure`, is defined by graft itself, not by
the user's contract. The `graft:` prefix keeps it out of the user's
namespace. Each measure is one record with fields:

- `id` — `measure:<name>`.
- `name` — unique short name; the enum value the model selects.
- `title` — human-readable label.
- `description` — what the model and the reviewer read to decide whether
  this measure answers a question.
- `target_class` — the contract class the measure computes over.
- `expr` — the calculation, in the declarative expression language below.
- `parameters` — JSON array of model-suppliable arguments; each entry has
  `name`, `type`, `description`, and `column` (the filterable column of the
  target class the argument binds to). In v1 a supplied argument always
  binds as an equality predicate on its column; range or pattern predicates
  are out of scope.
- `dimensions` — character vector of columns of the target class the caller
  may group by. May be empty.

Because measures are ordinary records, they inherit the full lifecycle:
proposed via `graft_plan()`, reviewed, accepted via `graft_commit()`, with
provenance and immutable revision history. `graft_history()` answers "who
changed this metric definition and when". An agent proposing a measure is an
agent proposing a record; nothing new is required of the review surface.

### Seeding from the contract

Contract-supplied `definitions` (from data-dict resolved JSON) do not get a
separate read-only path. At `graft_open()`, any definitions present in the
contract are auto-committed as seed measure records with
`producer = "contract"` and an idempotency key derived from the contract
digest. Reopening the same store with the same contract is a no-op. A later
contract change proposes updates through the normal plan flow rather than
silently mutating accepted state. There is one list of measures and one
lifecycle.

## Expression language

Graft implements its own small parser and compiler with no new package
dependencies. The accepted grammar is a strict subset of the data-dict
definition expression language:

- column references of the target class
- literals (numeric, string, boolean)
- arithmetic (`+`, `-`, `*`, `/`), comparison (`=`, `!=`, `<`, `<=`, `>`,
  `>=`), and boolean (`AND`, `OR`, `NOT`) operators
- a whitelisted set of aggregates: `SUM`, `COUNT`, `COUNT(DISTINCT ...)`,
  `AVG`, `MIN`, `MAX`

Nothing else is accepted: no function calls outside the whitelist, no
subqueries, and no cross-class joins in v1.

### Validation (plan time)

Validation runs at plan time, before human review:

- the expression must parse against the grammar above;
- every column reference must resolve against the contract's declaration of
  `target_class`;
- every parameter's `column` and every entry in `dimensions` must name a
  real filterable/groupable column of the target class.

An invalid measure produces rows in `plan@issues` with specific issue
classes, exactly like a dangling reference does today. The plan is invalid
and nothing executes.

### Compilation (call time)

Compilation to DuckDB SQL happens at evaluation time, against the
accepted-state view of the target class only — never staged data. Because
expressions were validated at plan time, a SQL-level failure at call time
indicates a graft bug, and the error message says so.

## Evaluation semantics

`graft_measure(store, name, arguments = list(), by = NULL)` evaluates over
accepted state at head, or over a pinned boundary when given a snapshot or
`graft_at()` handle — the same rule as every other graft read.

- `arguments` bind only to declared parameters, as equality predicates on
  their bound columns.
- `by` may name only declared dimensions.
- The result is a data frame plus receipt fields: `store_schema_digest`
  (as on every graft read), widened for measures with `measure_id` and the
  measure's `revision_id`, so an answer can later be traced to the exact
  definition in force when it was computed. Widening receipts on all other
  tools (commit/snapshot ids) is phase 2, not this spec.

Evaluation is read-only and deterministic: same boundary, same definition,
same arguments → same answer.

## API and tool surface

Three user-facing functions and one new tool:

- `graft_measures(store)` — list accepted measures: name, title,
  description, target class, parameters, dimensions.
- `graft_measure(store, name, arguments = list(), by = NULL)` — evaluate
  one measure.
- No authoring helper in v1: a measure is proposed as a plain record in a
  `graft:measure` batch through `graft_plan()`.

`graft_tools()` gains a fifth tool, `graft_measure`, built like the existing
four: measure name as an enum of currently accepted measures, parameters
described from the stored definitions, annotated read-only, non-destructive,
idempotent, and closed-world, with results in the standard
`result`/`truncated`/`limit`/receipt shape. If the store has no accepted
measures, the tool is omitted from the returned list.

## Error handling

Two failure surfaces, kept apart:

- **Plan time** (proposing a measure): parse errors, unknown columns,
  non-whitelisted functions, and bad parameter/dimension declarations become
  rows in `plan@issues` with specific classes — never an R error.
- **Call time** (evaluating): unknown measure name, an argument that does
  not match a declared parameter, or `by` outside declared dimensions raise
  classed conditions following the package's existing `conditions.R`
  patterns, with messages naming what was allowed.

## Testing

Following the house test layout:

- `tests/testthat/test-measures.R` — data model, seeding from contract,
  plan-time validation (via `expect_snapshot` for issue output).
- `tests/testthat/test-measure-eval.R` — compilation and evaluation against
  a small in-memory store; determinism under a pinned snapshot; receipt
  fields.
- Additions to the existing agent-tools tests: the fifth tool's shape, and
  its omission when the store has no measures.
- The expression parser gets its own table of accept/reject cases.
- Snapshot tests for all user-facing errors.

## Out of scope for phase 1

- Trust tagging and receipt widening on non-measure tools (phase 2).
- R-function measures, roxygen `@measure` loading, and provenance permalink
  tags (phase 3).
- Commons `data_source` interop (phase 3).
- Cross-class joins, subqueries, window functions, or user-extensible
  function whitelists in the expression language.
- UI of any kind.
