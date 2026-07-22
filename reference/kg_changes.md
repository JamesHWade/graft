# List accepted record changes

`kg_changes()` returns immutable record revisions in deterministic
newest-first commit order. Historical records and changed-field names
are filtered using the exact manifest that governed each revision, so
sensitive slots are not exposed.

## Usage

``` r
kg_changes(
  store,
  batch_id = NULL,
  record_id = NULL,
  class = NULL,
  from = NULL,
  to = NULL,
  limit = 100
)
```

## Arguments

- store:

  An initialized `kg_store`.

- batch_id:

  Optional exact committed batch identifier.

- record_id:

  Optional exact internal record identifier.

- class:

  Optional exact historical concrete class name.

- from, to:

  Optional inclusive `POSIXt` boundaries on batch commit time.

- limit:

  Maximum number of revisions to return.

## Value

A bounded data frame with `changed_fields` and `record` list-columns.
