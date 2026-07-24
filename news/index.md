# Changelog

## graft 0.0.0.9000

- A provider-free continuous-intelligence example, staged operator
  walkthrough, and interactive Shiny Briefing Room demonstrate scheduled
  Tempest briefings, host-bound promotion and approval, evidence-checked
  decisions, and governed Graft ingestion.
- Store format 2 adds complete system-time revision history and rejects
  stores created by earlier development versions instead of silently
  upgrading or operating in a legacy mode.
- [`kg_apply_migration()`](https://jameshwade.github.io/graft/reference/kg_apply_migration.md)
  atomically applies an unmodified reviewed migration plan after
  revalidating its digest and store preconditions; the first migration
  version accepts only compatible and supported additive changes.
- [`kg_batch()`](https://jameshwade.github.io/graft/reference/kg_batch.md)
  creates stable producer batches, and
  [`kg_ingest()`](https://jameshwade.github.io/graft/reference/kg_ingest.md)
  atomically reconciles, validates, and upserts multiple record classes
  with identifier, origin, observation, and replay lineage.
- [`kg_batches()`](https://jameshwade.github.io/graft/reference/kg_batches.md)
  and
  [`kg_changes()`](https://jameshwade.github.io/graft/reference/kg_changes.md)
  provide bounded, newest-first provenance and revision views with
  historical schema-aware sensitivity filtering.
- [`kg_check_store()`](https://jameshwade.github.io/graft/reference/kg_check_store.md)
  reports bounded revision-ledger and current-state integrity findings,
  with an optional deep payload and projection check.
- [`kg_claims()`](https://jameshwade.github.io/graft/reference/kg_claims.md),
  [`kg_evidence()`](https://jameshwade.github.io/graft/reference/kg_evidence.md),
  and
  [`kg_competing_claims()`](https://jameshwade.github.io/graft/reference/kg_competing_claims.md)
  retrieve bounded narrative and semantic assertions, stored citations,
  and non-adjudicated comparison sets while preserving qualifiers and
  ordinary attributes.
- [`kg_compile_schema()`](https://jameshwade.github.io/graft/reference/kg_compile_schema.md)
  compiles ordinary LinkML schemas into deterministic, portable graft
  manifests without requiring graft-specific imports or annotations;
  graft core roles remain available for richer claim, evidence, and
  graph behavior.
- [`kg_connect_duckdb()`](https://jameshwade.github.io/graft/reference/kg_connect_duckdb.md),
  [`kg_init()`](https://jameshwade.github.io/graft/reference/kg_init.md),
  and
  [`kg_disconnect()`](https://jameshwade.github.io/graft/reference/kg_disconnect.md)
  provide an ownership-aware DuckDB store lifecycle with manifest-driven
  initialization and structural schema protection.
- [`kg_context()`](https://jameshwade.github.io/graft/reference/kg_context.md)
  generates a token-bounded, sensitive-field-safe description of the
  active manifest and DuckDB access constraints.
- [`kg_edges()`](https://jameshwade.github.io/graft/reference/kg_edges.md),
  [`kg_nodes()`](https://jameshwade.github.io/graft/reference/kg_nodes.md),
  [`kg_neighbors()`](https://jameshwade.github.io/graft/reference/kg_neighbors.md),
  [`kg_traverse()`](https://jameshwade.github.io/graft/reference/kg_traverse.md),
  and
  [`kg_subgraph()`](https://jameshwade.github.io/graft/reference/kg_subgraph.md)
  provide lazy manifest-driven graph projections plus deterministic,
  explicitly collected one-hop and two-hop retrieval with hard node and
  edge caps.
- [`kg_find()`](https://jameshwade.github.io/graft/reference/kg_find.md),
  [`kg_lookup()`](https://jameshwade.github.io/graft/reference/kg_lookup.md),
  and
  [`kg_identifiers()`](https://jameshwade.github.io/graft/reference/kg_identifiers.md)
  provide bounded manifest-declared search and exact identifier
  resolution with registry provenance.
- [`kg_get()`](https://jameshwade.github.io/graft/reference/kg_get.md)
  hydrates exactly one public record with bounded related identifiers,
  claims, and evidence.
- [`kg_history()`](https://jameshwade.github.io/graft/reference/kg_history.md)
  retrieves bounded revisions for one record and recovers its accepted
  state at a committed batch or time boundary.
- [`kg_init()`](https://jameshwade.github.io/graft/reference/kg_init.md)
  verifies structural-digest integrity and compiler-required physical
  type contracts before creating or changing store objects.
- [`kg_ingest_tempest_records()`](https://jameshwade.github.io/graft/reference/kg_ingest_tempest_records.md)
  commits mapped Tempest domain records with run- and stage-stable
  idempotency keys, independently of Tempest deliverable persistence.
- [`kg_plan_migration()`](https://jameshwade.github.io/graft/reference/kg_plan_migration.md)
  creates a deterministic, serializable migration plan bound to the
  store identity, format, active schema, and exact target manifest.
- [`kg_records()`](https://jameshwade.github.io/graft/reference/kg_records.md)
  returns lazy typed dbplyr tables for public concrete classes.
- [`kg_schema()`](https://jameshwade.github.io/graft/reference/kg_schema.md),
  [`kg_classes()`](https://jameshwade.github.io/graft/reference/kg_classes.md),
  [`kg_slots()`](https://jameshwade.github.io/graft/reference/kg_slots.md),
  [`kg_enums()`](https://jameshwade.github.io/graft/reference/kg_enums.md),
  and
  [`kg_schema_info()`](https://jameshwade.github.io/graft/reference/kg_schema_info.md)
  load and inspect manifests without Python.
- [`kg_schema_diff()`](https://jameshwade.github.io/graft/reference/kg_schema_diff.md)
  reports structural schema changes with deterministic per-change and
  overall compatibility classifications.
- [`kg_select()`](https://jameshwade.github.io/graft/reference/kg_select.md)
  provides a collected, hard-capped structured query surface with
  manifest validation and no arbitrary SQL.
- [`kg_store_info()`](https://jameshwade.github.io/graft/reference/kg_store_info.md)
  reports the store format, exact active schema build, and
  revision-history coverage in addition to connection and schema
  details;
  [`kg_capabilities()`](https://jameshwade.github.io/graft/reference/kg_capabilities.md)
  reports static backend capabilities.
- [`kg_tools()`](https://jameshwade.github.io/graft/reference/kg_tools.md)
  creates six read-only ellmer tools over bounded Graft retrieval APIs,
  with structured results and no arbitrary SQL surface.
- [`kg_unresolved()`](https://jameshwade.github.io/graft/reference/kg_unresolved.md)
  returns bounded unresolved mention records.
- [`kg_validate_data()`](https://jameshwade.github.io/graft/reference/kg_validate_data.md)
  preflights the same staged identity, shape, and reference checks as
  ingestion without mutating the store.
- [`kg_write()`](https://jameshwade.github.io/graft/reference/kg_write.md)
  provides a one-class convenience wrapper over
  [`kg_ingest()`](https://jameshwade.github.io/graft/reference/kg_ingest.md).
- [`tempest_artifact_store_graft()`](https://jameshwade.github.io/graft/reference/tempest_artifact_store_graft.md)
  explicitly reports the upstream Tempest serialization contract
  required before durable typed-artifact persistence can be supported.
