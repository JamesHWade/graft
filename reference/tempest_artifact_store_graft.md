# Create a Graft-backed Tempest artifact-store adapter

The current Tempest artifact-store callback receives a typed artifact
but not the deliverable specification required for validated
reconstruction. Graft therefore refuses to construct an adapter until
Tempest exposes a complete, versioned public serialization contract. It
does not use internal Tempest helpers, fabricate a specification, or
store opaque R serialization.

## Usage

``` r
tempest_artifact_store_graft(store)
```

## Arguments

- store:

  An initialized, writable `kg_store`.

## Value

This implementation does not return. It aborts with
`graft_tempest_dependency_error` when Tempest is unavailable, or
`graft_tempest_artifact_store_unsupported` because the current public
Tempest API lacks the required durable contract.

## Details

Use
[`kg_ingest_tempest_records()`](https://jameshwade.github.io/graft/reference/kg_ingest_tempest_records.md)
for the supported multi-run knowledge handoff.
