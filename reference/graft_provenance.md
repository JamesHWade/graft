# Describe the provenance of a candidate knowledge change

Provenance identifies the producer and optional upstream run that
supplied a candidate change. The producer and idempotency key form the
replay boundary when a reviewed plan is committed.

## Usage

``` r
graft_provenance(
  producer,
  version = NULL,
  run_id = NULL,
  idempotency_key = NULL,
  metadata = list()
)
```

## Arguments

- producer:

  One non-empty producer name.

- version:

  Optional producer version.

- run_id:

  Optional producer-side run identifier.

- idempotency_key:

  Optional key identifying a replay for this producer.

- metadata:

  A named JSON-serializable metadata list.

## Value

An immutable `GraftProvenance` S7 object.
