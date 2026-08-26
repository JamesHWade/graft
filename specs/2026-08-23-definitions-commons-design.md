# Composable definitions and Commons interoperability

Date: 2026-08-23
Status: approved design, Phase 3 of 3

## Purpose

Phase 3 replaces Graft's independently agent-ready measure abstraction with a
composable semantic layer over accepted knowledge. Metrics need not carry
their own parameter and dimension allowlists. Callers may combine same-table
metrics, filters, derived values, dimensions, and simple predicates, as they do
in Commons.

Graft extends that interaction with accepted definition history, immutable
boundaries, and Receipts. It does not take ownership of Commons file measures,
fallback query paths, trust labels, or agent behavior.

The design was checked against 30 model-driven traces spanning OpenAI and
Anthropic models, global and target-scoped Graft tools, and a pinned Commons
installation. Those traces supported the Commons-shaped calculation surface,
plain-string discovery, same-table composition, and narrow meaning of
Verified. Perfect prompt obedience is not an invariant.

## Domain model

### Definitions

`GraftDefinition` is a reserved Graft system record with these authored
fields:

- `name`: required name local to one public table;
- `target`: required public-table name;
- `expr`: required data-dict expression;
- `label`: optional display label;
- `description`: optional concise explanation; and
- `details`: optional extended explanation.

Graft derives the record identity, kind, and dependencies. `target + name` is
the stable semantic identity. Changing the expression or documentation creates
a new revision of the same definition. Renaming or retargeting creates a new
definition.

Names may not shadow columns. A definition may reference sibling definitions
on the same target. The dependency graph must be acyclic and is validated at
plan time. Graft infers one of three kinds from the expression:

- `metric`: an aggregate calculation;
- `filter`: a boolean predicate; or
- `derived`: a row-level value available for grouping or composition.

Definitions declared in the source data-dict seed accepted definition records
with contract provenance when a new store is initialized. Reopening an existing
store does not accept changed definitions; those changes go through the normal
plan and commit flow.
Subsequent discovery and evaluation read accepted ledger revisions rather than
rereading a mutable external dictionary.

### Expression contract

Definitions use the pinned data-dict expression contract. This is data-dict
compatibility, not a Commons-owned language. Graft validates and executes that
contract and exports the same expression without reinterpretation. Stored SQL
and executable R are not definition languages.

The data-dict provider revision and resolved contract remain part of Graft's
schema identity. An expression that is invalid for that pinned contract makes
the plan invalid; nothing executes during planning.

### Public tables

A definition targets one public table. Public tables include concrete class
projections and selected normalized relation projections declared by Graft's
public contract. System, sensitive, and internal tables and columns are never
eligible.

One evaluation operates over one public table. Cross-table definitions, joins,
and polymorphic targets are out of scope. This restriction makes the accepted
definition closure and data boundary exact without presuming that individual
metrics must be independently agent-ready.

## Public API

### Discover definitions

```r
graft_definitions(source, target = NULL)
```

The function returns a bounded catalog. `target` optionally filters it to one
public table. The catalog exposes:

- definition ID and accepted revision ID;
- name, target, and inferred kind;
- expression, label, description, and details;
- direct dependencies; and
- eligible public columns for the target.

Definitions are ordered deterministically by target and name. Names are local
to a target. `target::name` is the unambiguous external spelling when the same
name appears on multiple tables.

### Calculate

```r
graft_calculate(
  source,
  metrics,
  dimensions = NULL,
  filters = NULL,
  where = NULL
)
```

This mirrors Commons's calculation interface. At least one metric is required.
Graft resolves the metrics first and infers the target table. Every metric must
resolve to the same target. Dimensions, filters, and predicates then resolve
within that target.

`metrics` contains metric definition names. `dimensions` may contain public
scalar columns or derived definitions. `filters` contains filter definition
names. Ambiguous definition names may be qualified as `target::name`.

`where` is a list of predicates with exactly these fields:

- `column`: required string naming a public scalar column;
- `op`: one of `=`, `!=`, `<`, `<=`, `>`, and `>=`; and
- `value`: required string, including numbers and dates as plain strings.

Predicates are combined with AND. Graft parses and binds each value using the
data-dict column type. Invalid or ambiguous coercions fail instead of relying
on DuckDB implicit casts. More complex logic belongs in an accepted filter
definition.

Result columns place dimensions first and metrics second, each in request
order. Ungrouped calculations return one row. Grouped rows sort
deterministically by their dimensions. A grouped result beyond Graft's hard
row bound fails closed; the API has no `limit` argument and never returns a
truncated calculation that could be mistaken for a complete result.

Unknown names, mixed targets, wrong definition kinds, invalid predicates,
cycles, type failures, and execution failures raise classed Graft conditions.
A failed calculation has no valid Receipt. Attempt metadata may be retained
for diagnostics but is not verification evidence.

### Agent tools

When accepted definitions exist, `graft_tools()` exposes
`graft_definitions` and one `graft_calculate` tool alongside the existing
generic read tools. It does not generate one tool per table. Arguments are
plain strings rather than enums generated from mutable accepted state. The
agent discovers names, targets, meanings, and eligible columns from the
bounded catalog.

## Receipts and verification

A successful calculation carries the canonical Graft Receipt for its exact
accepted boundary. Its `definitions` array contains every explicitly selected
and transitively referenced accepted definition. Each entry contains:

- definition ID;
- accepted revision ID; and
- inferred kind.

Entries are sorted canonically by definition ID. Public columns and `where`
predicates remain calculation inputs and do not become synthetic definitions.
The singular Phase 2 `definition` field is removed.

`Verified` continues to mean that an answer's evidence path consists
exclusively of successful governed calculations with valid Receipts. It does
not mean prompt obedience, semantic fidelity, factual correctness, or
authentication of receipt identifiers. Commons traces and Commons trust labels
do not become Graft Receipts or Graft Verification evidence.

## Commons adapter

```r
graft_commons_data_source(source, classes = NULL)
```

The adapter is the only Graft-to-Commons API. Commons is optional. Callers pass
file measures and construct a Commons semantic layer directly through Commons.
Graft does not wrap, ingest, or govern executable R.

The adapter captures one accepted boundary and materializes a detached,
Commons-owned query copy:

1. Select all concrete public classes by default, or the classes requested by
   `classes`.
2. Include the selected class projections and applicable normalized public
   relation projections.
3. Exclude every system, sensitive, and internal table or column.
4. Materialize every selected table atomically, including typed zero-row
   tables. Any projection failure aborts the complete construction.
5. Generate a temporary data-dict document containing public schemas,
   relationships, prose, and accepted definitions at that boundary.
6. Pass detached data frames and the dictionary path through Commons's public
   `data_source()` constructor so Commons creates and hardens its own DuckDB
   connection.
7. Return only the concrete Commons data source.

Graft never passes its live DuckDB connection to Commons. Later commits do not
change an existing source; callers construct a new source to refresh it.

The adapter uses only exported Commons APIs. CI installs and tests an exact
pinned Commons commit. Runtime checks fail clearly when the installed public
contract is incompatible; Graft does not parse unstable Commons errors or
couple to internal object layouts.

## Migration

Phase 3 is a hard cut. Remove:

- `GraftMeasure`;
- `graft_measures()`;
- `graft_measure()`;
- per-measure parameter declarations;
- per-measure dimension allowlists;
- the generated single-measure tool; and
- the singular Receipt `definition` field.

Add:

- `GraftDefinition`;
- `graft_definitions()`;
- `graft_calculate()`;
- the discovery and composite calculation tools;
- the Receipt `definitions` array; and
- `graft_commons_data_source()`.

No aliases or transitional dual model remain. Graft is pre-production, and
keeping both abstractions would create conflicting authority and provenance
contracts.

## Implementation sequence

1. Replace the reserved measure record with the definition record and migrate
   data-dict seeding and plan validation.
2. Generalize expression validation and compilation to the pinned data-dict
   contract, including dependency and kind inference.
3. Implement the bounded definition catalog and composite evaluator against
   live and pinned accepted boundaries.
4. Replace the measure tool and receipt field, then update deterministic
   verification for the new calculation evidence path.
5. Implement detached public-table materialization and the optional Commons
   adapter.
6. Remove the old public surface, regenerate documentation, and update the
   package site and release notes.

## Verification plan

Tests must cover:

- contract seeding, deterministic identity, revision history, rename and
  retarget behavior;
- data-dict expression acceptance, kind inference, dependencies, cycles,
  column shadowing, and same-target enforcement;
- multiple metrics, derived dimensions, filters, typed `where` predicates,
  result ordering, pinned boundaries, empty data, and hard row-bound failure;
- exact transitive Receipt closure and rejection of failed calculations as
  verification evidence;
- bounded catalog and plain-string agent tool schemas;
- public and sensitive projection boundaries, normalized relations, typed
  empty tables, atomic adapter failure, and source immutability after commits;
- exact pinned Commons construction through public APIs; and
- removal of every legacy export, class, tool, receipt field, test fixture,
  reference topic, and release-note claim.

The implementation is complete only after focused tests, the full package
suite, `air format .`, regenerated documentation, pkgdown validation,
`git diff --check`, and R CMD check pass.

## Out of scope

- Cross-table definition composition or joins.
- Executable R as a governed Graft record.
- Graft ownership of Commons file measures or agent fallback paths.
- Requiring perfect model adherence to tool instructions.
- Treating Verification as fact-checking or semantic validation.
- Incrementally refreshing a Commons source.
- Backward-compatible measure aliases.
