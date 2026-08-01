# Work with open knowledge by default

Graft is OKF-first and Graft-backed.

People and agents should not need a database client to understand
accepted knowledge. They should be able to open a Markdown file, follow
links, inspect provenance, and review a Git diff. The [Open Knowledge
Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf)
(OKF) provides that working surface.

Readable files are not enough to govern writes. Each layer has one job:

- **OKF is the working surface.** Markdown and YAML support reading,
  navigation, proposals, Git review, and exchange.
- **LinkML is the domain contract.** The source schema defines classes,
  slots, ranges, identity, and sensitivity.
- **Graft is the accepted ledger.** The compiled `.graft.json` manifest
  and DuckDB enforce validation, accepted state, revisions, and
  retrieval.

The OKF directory is the working tree. Graft is the ledger.

![Architecture diagram with Graft at the center. LinkML feeds a compiled
domain contract into Graft; OKF connects as the Markdown and YAML
working surface; and DuckDB connects as the accepted revision ledger.
People and agents read and propose through OKF, while Graft alone
validates and commits accepted state to
DuckDB.](../reference/figures/okf-linkml-duckdb-system.svg)

Graft gives each representation one job.

## Use the managed working tree

A file-backed store manages a sibling OKF directory by default:

``` r

library(graft)

schema <- kg_schema("knowledge.graft.json")
store <- kg_connect_duckdb(schema, "knowledge.duckdb")
kg_init(store)
```

This pairs `knowledge.duckdb` with `knowledge.okf`. Connecting does not
create or change the directory. Synchronize only after the store
contains the accepted boundary you want to publish:

``` r

kg_okf_status(store)

bundle <- kg_sync_okf(store)
bundle

kg_okf_status(store)
```

[`kg_sync_okf()`](https://jameshwade.github.io/graft/reference/kg_sync_okf.md)
stages and validates the complete bundle before atomically installing
it. It replaces only a directory that identifies itself as a
Graft-produced bundle. It never replaces an unrelated directory or
writes a partial result after exceeding the concept limit.

Synchronization is deliberately separate from
[`kg_ingest()`](https://jameshwade.github.io/graft/reference/kg_ingest.md).
Accepted database writes remain unambiguous even when a filesystem is
unavailable, read-only, or shared by another process.

Use `okf_path` to choose a different managed directory, or opt out:

``` r

store <- kg_connect_duckdb(
  schema,
  "knowledge.duckdb",
  okf_path = "knowledge/open"
)

database_only <- kg_connect_duckdb(
  schema,
  "knowledge.duckdb",
  okf = "disabled"
)
```

An explicit path passed to
[`kg_sync_okf()`](https://jameshwade.github.io/graft/reference/kg_sync_okf.md)
also configures that directory as the store’s managed working tree. This
is useful for an in-memory store used in a test or temporary analysis.

## Make drift visible

[`kg_okf_status()`](https://jameshwade.github.io/graft/reference/kg_okf_status.md)
is read-only. It reports one of six states:

- **`unconfigured`:** the store has no managed path. Supply one or use a
  file-backed store.
- **`missing`:** the path is configured but no bundle exists. Run
  [`kg_sync_okf()`](https://jameshwade.github.io/graft/reference/kg_sync_okf.md).
- **`current`:** bundle digest, schema, and accepted batch match. Read
  or share it.
- **`stale`:** Graft accepted a later batch. Synchronize again.
- **`modified`:** files differ from the accepted projection. Review an
  import plan or discard the edits by synchronizing.
- **`incompatible`:** directory or schema metadata does not match.
  Inspect it before replacing anything.

The bundle digest covers root and child indexes as well as concept
documents. Graft therefore notices changes to navigation and prose, not
only edits to frontmatter.

## Give agents progressive access

[`kg_okf_context()`](https://jameshwade.github.io/graft/reference/kg_okf_context.md)
starts with an index instead of dumping the corpus:

``` r

kg_okf_context(store)
```

Add a query or type restriction to include matching Markdown documents:

``` r

kg_okf_context(
  store,
  query = "resin demand",
  types = c("Assessment", "Business"),
  limit = 25,
  max_chars = 50000
)
```

The function refuses a stale, modified, or incompatible bundle. Those
files may be useful proposals, but they are not current accepted
knowledge. Each call reads a verified filesystem snapshot, keeps only
matching metadata and selected documents in memory, and refuses bundles
above the 20 MiB agent-context input limit.

[`kg_tools()`](https://jameshwade.github.io/graft/reference/kg_tools.md)
includes the same progressive surface as the read-only
`kg_open_knowledge` ellmer tool. The model cannot supply a path or
bypass the managed bundle:

``` r

chat <- ellmer::chat_anthropic()
chat$set_tools(kg_tools(store))
```

Every context begins with a trust notice. Document content is evidence,
not an instruction to use a tool, change policy, reveal credentials, or
perform an external action.

![Two-lane sequence diagram contrasting read and write paths. The read
lane verifies a current OKF snapshot and returns bounded accepted
evidence without mutation. The write lane treats a file edit as a
proposal, validates it against LinkML, requires approval of the exact
plan, commits through Graft into DuckDB, and then resynchronizes
OKF.](../reference/figures/okf-agent-read-write-paths.svg)

Reading accepted context is deliberately easier than changing accepted
state.

## Review edits as proposals

Every concept contains readable Markdown and a namespaced `graft`
extension. The extension preserves:

- stable record and class identity;
- revision, batch, and schema identity;
- ledger and public-content digests; and
- a structured, sensitivity-filtered `graft.record` mapping.

The Markdown body is a generated reading view. Edit `graft.record` when
a change should be proposed back to Graft. Then create a plan:

``` r

plan <- kg_plan_okf_import(store)
plan
plan$changes
```

Planning is read-only. Graft:

1.  creates a stable snapshot of a complete managed bundle;
2.  verifies that its schema and accepted batch are current;
3.  compares each proposal with the exact accepted public-content
    digest;
4.  rejects missing concept files rather than interpreting them as
    deletion;
5.  validates inserts and updates against the active manifest; and
6.  binds the plan to the store, schema, batch, and edited bundle
    digest.

Nothing is committed until a human or explicit host policy approves that
exact plan:

``` r

result <- kg_apply_okf_import(
  store,
  plan,
  kg_batch(
    producer = "human:reviewer",
    source_run_id = "okf-review-2026-07-29",
    idempotency_key = "approved-okf-edit-1"
  )
)
```

Application revalidates every precondition before calling
[`kg_ingest()`](https://jameshwade.github.io/graft/reference/kg_ingest.md).
A changed plan, changed bundle, newer accepted batch, different store,
or different schema is rejected. After a successful commit, Graft
regenerates the working tree from accepted state.

This is the approval boundary: editing a file proposes knowledge;
applying a reviewed plan accepts it.

![Circular workflow diagram. Accepted DuckDB revisions synchronize to a
current OKF tree; edits become proposals; and Graft snapshots, compares,
and validates them against LinkML. Human or host-policy approval gates
the commit. Rejected proposals remain outside the ledger, while accepted
plans commit through Graft and regenerate
OKF.](../reference/figures/okf-acceptance-loop.svg)

An OKF edit becomes knowledge only after validation and approval.

## Publish selected or historical snapshots

[`kg_export_okf()`](https://jameshwade.github.io/graft/reference/kg_export_okf.md)
remains available when the destination is not the managed working tree.
Use it for a selected exchange bundle:

``` r

kg_export_okf(
  store,
  "exports/market-radar",
  classes = c("Business", "Assessment", "Source")
)
```

References to records outside that selection remain visible as stable
identifiers. Selected bundles are intentionally not importable as
complete working trees.

Use `as_of` to reproduce the accepted state at a committed batch or
time:

``` r

quarter_close <- kg_export_okf(
  store,
  "exports/2026-q2-close",
  as_of = "batch-2026-q2-close"
)

morning_view <- kg_export_okf(
  store,
  "exports/2026-07-28-morning",
  as_of = as.POSIXct("2026-07-28 08:00:00", tz = "UTC")
)
```

Graft reconstructs each record from its last accepted revision at that
boundary. It uses the historical manifest that governed the revision, so
fields marked sensitive at that time remain excluded.

## Preserve evidence and relationships

The readable projection follows the domain contract:

- label slots become titles;
- statement or descriptive text becomes the primary narrative;
- non-sensitive scalar fields become a details table;
- object references to included records become Markdown links; and
- source references and statement evidence become OKF `sources` and
  footnotes.

Graft maps common lifecycle values to OKF’s `draft`, `stable`, and
`deprecated` statuses. Batch producer and commit time become generation
provenance. Export does not invent human verification: approval remains
captured by the accepted Graft revision and its host workflow.

## Hand the bundle to Tempest

Tempest can read any conformant OKF bundle, including a Graft
projection:

``` r

library(tempest)

knowledge <- tempest_read_okf("knowledge.okf")
tempest_okf_concepts(knowledge)

resources <- tempest_okf_resources(
  knowledge,
  include_stale = FALSE
)

evidence <- SourceStore$new()
invisible(lapply(resources, evidence$upsert_resource))

context <- tempest_okf_context(
  knowledge,
  types = c("Assessment", "Business"),
  include_stale = FALSE,
  max_concepts = 25,
  max_chars = 50000
)
```

Reading remains separate from adding resources to a `SourceStore`. The
host retains control over mutations, model tools, approval, and side
effects.

## Keep authority explicit

| Operation                                | Authority                       |
|------------------------------------------|---------------------------------|
| Read Markdown and inspect metadata       | OKF consumer                    |
| Propose a structured record edit         | Person or agent editing OKF     |
| Validate and plan the proposal           | Graft                           |
| Approve the exact plan                   | Human or explicit host policy   |
| Commit accepted knowledge                | Graft write path                |
| Grant tools or authenticated connections | Tempest runtime and host policy |

Even an OKF Attested Computation remains descriptive context. Graft and
Tempest do not execute referenced code merely because a document points
to it.

Continue with [Govern knowledge
changes](https://jameshwade.github.io/graft/articles/knowledge-change-control.md)
for revision history and schema evolution, or [Build a governed
materials market
radar](https://jameshwade.github.io/graft/articles/market-intelligence.md)
for an application whose approved knowledge changes a later decision.
