# graft 0.0.0.9000

* A provider-free continuous-intelligence example and staged operator walkthrough demonstrate scheduled Tempest briefings, host-bound promotion and approval, evidence-checked decisions, and governed Graft ingestion.
* `kg_batch()` creates stable producer batches, and `kg_ingest()` atomically
  reconciles, validates, and upserts multiple record classes with identifier,
  origin, observation, and replay lineage.
* `kg_claims()`, `kg_evidence()`, and `kg_competing_claims()` retrieve bounded
  narrative and semantic assertions, stored citations, and non-adjudicated
  comparison sets while preserving qualifiers and ordinary attributes.
* `kg_compile_schema()` compiles ordinary LinkML schemas into deterministic, portable graft manifests without requiring graft-specific imports or annotations; graft core roles remain available for richer claim, evidence, and graph behavior.
* `kg_connect_duckdb()`, `kg_init()`, and `kg_disconnect()` provide an
  ownership-aware DuckDB store lifecycle with manifest-driven initialization
  and structural schema protection.
* `kg_context()` generates a token-bounded, sensitive-field-safe description
  of the active manifest and DuckDB access constraints.
* `kg_edges()`, `kg_nodes()`, `kg_neighbors()`, `kg_traverse()`, and `kg_subgraph()` provide lazy manifest-driven graph projections plus deterministic, explicitly collected one-hop and two-hop retrieval with hard node and edge caps.
* `kg_find()`, `kg_lookup()`, and `kg_identifiers()` provide bounded
  manifest-declared search and exact identifier resolution with registry
  provenance.
* `kg_get()` hydrates exactly one public record with bounded related
  identifiers, claims, and evidence.
* `kg_ingest_tempest_records()` commits mapped Tempest domain records with
  run- and stage-stable idempotency keys, independently of Tempest deliverable
  persistence.
* `kg_records()` returns lazy typed dbplyr tables for public concrete classes.
* `kg_schema()`, `kg_classes()`, `kg_slots()`, `kg_enums()`, and
  `kg_schema_info()` load and inspect manifests without Python.
* `kg_schema_diff()` reports structural schema changes.
* `kg_select()` provides a collected, hard-capped structured query surface
  with manifest validation and no arbitrary SQL.
* `kg_store_info()` and `kg_capabilities()` inspect DuckDB stores without
  requiring Python.
* `kg_tools()` creates six read-only ellmer tools over bounded Graft retrieval
  APIs, with structured results and no arbitrary SQL surface.
* `kg_unresolved()` returns bounded unresolved mention records.
* `kg_validate_data()` preflights the same staged identity, shape, and
  reference checks as ingestion without mutating the store.
* `kg_write()` provides a one-class convenience wrapper over `kg_ingest()`.
* `tempest_artifact_store_graft()` explicitly reports the upstream Tempest
  serialization contract required before durable typed-artifact persistence
  can be supported.
