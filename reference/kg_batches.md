# List committed ingestion batches

`kg_batches()` returns committed batches in deterministic newest-first
commit order. Batch metadata is parsed into a list-column; the stored
JSON is never exposed directly.

## Usage

``` r
kg_batches(
  store,
  producer = NULL,
  source_run_id = NULL,
  from = NULL,
  to = NULL,
  limit = 100
)
```

## Arguments

- store:

  An initialized `kg_store`.

- producer:

  Optional exact producer name.

- source_run_id:

  Optional exact producer-side run identifier.

- from, to:

  Optional inclusive `POSIXt` boundaries on commit time.

- limit:

  Maximum number of batches to return.

## Value

A bounded data frame of committed batch provenance.
