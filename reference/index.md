# Package index

## Schema

Compile, load, compare, and inspect the semantic contract that drives a
graft store.

- [`kg_compile_schema()`](https://jameshwade.github.io/graft/reference/kg_compile_schema.md)
  : Compile a LinkML schema into a graft manifest
- [`kg_schema()`](https://jameshwade.github.io/graft/reference/kg_schema.md)
  : Load a compiled graft schema manifest
- [`kg_schema_diff()`](https://jameshwade.github.io/graft/reference/kg_schema_diff.md)
  : Compare two compiled graft schemas
- [`kg_classes()`](https://jameshwade.github.io/graft/reference/kg_classes.md)
  : List concrete classes in a graft schema
- [`kg_slots()`](https://jameshwade.github.io/graft/reference/kg_slots.md)
  : List slots in a graft schema
- [`kg_enums()`](https://jameshwade.github.io/graft/reference/kg_enums.md)
  : List enum values in a graft schema
- [`kg_schema_info()`](https://jameshwade.github.io/graft/reference/kg_schema_info.md)
  : Summarize a graft schema

## Store lifecycle

Create and inspect ownership-aware DuckDB stores protected by structural
schema fingerprints.

- [`kg_connect_duckdb()`](https://jameshwade.github.io/graft/reference/kg_connect_duckdb.md)
  : Connect to a DuckDB knowledge store
- [`kg_init()`](https://jameshwade.github.io/graft/reference/kg_init.md)
  : Initialize or verify a graft store
- [`kg_disconnect()`](https://jameshwade.github.io/graft/reference/kg_disconnect.md)
  : Disconnect a graft store
- [`kg_store_info()`](https://jameshwade.github.io/graft/reference/kg_store_info.md)
  : Inspect a graft store
- [`kg_capabilities()`](https://jameshwade.github.io/graft/reference/kg_capabilities.md)
  : Report DuckDB store capabilities

## Ingestion and validation

Validate and atomically reconcile typed records with batch provenance
and idempotent replay.

- [`kg_batch()`](https://jameshwade.github.io/graft/reference/kg_batch.md)
  : Describe one atomic ingestion batch
- [`kg_ingest()`](https://jameshwade.github.io/graft/reference/kg_ingest.md)
  : Atomically ingest one or more record classes
- [`kg_ingest_tempest_records()`](https://jameshwade.github.io/graft/reference/kg_ingest_tempest_records.md)
  : Ingest records mapped from one Tempest run
- [`kg_write()`](https://jameshwade.github.io/graft/reference/kg_write.md)
  : Ingest one concrete record class
- [`kg_validate_data()`](https://jameshwade.github.io/graft/reference/kg_validate_data.md)
  : Validate records without writing them

## Records and identity

Retrieve lazy class tables, hydrate records, and resolve exact external
identifiers.

- [`kg_records()`](https://jameshwade.github.io/graft/reference/kg_records.md)
  : Read records from one concrete class
- [`kg_find()`](https://jameshwade.github.io/graft/reference/kg_find.md)
  : Search manifest-declared record text
- [`kg_get()`](https://jameshwade.github.io/graft/reference/kg_get.md) :
  Hydrate exactly one record
- [`kg_lookup()`](https://jameshwade.github.io/graft/reference/kg_lookup.md)
  : Look up an exact external identifier
- [`kg_identifiers()`](https://jameshwade.github.io/graft/reference/kg_identifiers.md)
  : List external identifiers for one record
- [`kg_unresolved()`](https://jameshwade.github.io/graft/reference/kg_unresolved.md)
  : List unresolved mentions

## Claims and evidence

Inspect narrative and semantic assertions together with their stored
supporting or challenging evidence.

- [`kg_claims()`](https://jameshwade.github.io/graft/reference/kg_claims.md)
  : Retrieve narrative and semantic claims about an entity
- [`kg_evidence()`](https://jameshwade.github.io/graft/reference/kg_evidence.md)
  : Retrieve evidence for one statement
- [`kg_competing_claims()`](https://jameshwade.github.io/graft/reference/kg_competing_claims.md)
  : Group candidate competing claims

## Graph projections

Traverse deterministic, bounded semantic and provenance projections over
the relational store.

- [`kg_nodes()`](https://jameshwade.github.io/graft/reference/kg_nodes.md)
  : Access the graph node projection
- [`kg_edges()`](https://jameshwade.github.io/graft/reference/kg_edges.md)
  : Access a graph edge projection
- [`kg_neighbors()`](https://jameshwade.github.io/graft/reference/kg_neighbors.md)
  : Retrieve a bounded graph neighborhood
- [`kg_traverse()`](https://jameshwade.github.io/graft/reference/kg_traverse.md)
  : Traverse a bounded predicate path
- [`kg_subgraph()`](https://jameshwade.github.io/graft/reference/kg_subgraph.md)
  : Collect a bounded induced subgraph

## Structured access

Describe the active knowledge contract and expose validated, bounded
access to applications and language models.

- [`kg_context()`](https://jameshwade.github.io/graft/reference/kg_context.md)
  : Describe the active knowledge contract
- [`kg_select()`](https://jameshwade.github.io/graft/reference/kg_select.md)
  : Perform a bounded structured selection
- [`kg_tools()`](https://jameshwade.github.io/graft/reference/kg_tools.md)
  : Create bounded ellmer tools for a graft store

## Tempest integration

Connect mapped Tempest domain records while preserving the current typed
artifact-store boundary.

- [`tempest_artifact_store_graft()`](https://jameshwade.github.io/graft/reference/tempest_artifact_store_graft.md)
  : Create a Graft-backed Tempest artifact-store adapter
