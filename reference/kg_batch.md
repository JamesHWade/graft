# Describe one atomic ingestion batch

A batch records producer provenance and supplies the idempotency
boundary for
[`kg_ingest()`](https://jameshwade.github.io/graft/reference/kg_ingest.md).
Its identifier is minted once and remains stable for the life of the
object.

## Usage

``` r
kg_batch(
  producer,
  producer_version = NULL,
  source_run_id = NULL,
  idempotency_key = NULL,
  metadata = list()
)
```

## Arguments

- producer:

  One non-empty producer name.

- producer_version:

  Optional producer version.

- source_run_id:

  Optional producer-side run identifier.

- idempotency_key:

  Optional key that identifies a replay for this producer.

- metadata:

  A list of JSON-serializable batch metadata.

## Value

A `kg_batch` object.
