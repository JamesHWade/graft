# List accepted changes between two boundaries

`graft_changes()` compares accepted knowledge at two committed
boundaries and returns one row per record whose accepted revision
differs between them. It answers "what was accepted since this snapshot"
for a whole store in one bounded table, where
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)
answers the same question for one record.

## Usage

``` r
graft_changes(
  store,
  since = NULL,
  until = NULL,
  class = NULL,
  limit = 1000L,
  record_ids = NULL
)
```

## Arguments

- store:

  An initialized `GraftStore` or immutable `GraftView`.

- since:

  Optional lower boundary, exclusive.

- until:

  Optional upper boundary, inclusive.

- class:

  Optional concrete class restriction.

- limit:

  Maximum changed records to return, up to the package hard limit.

- record_ids:

  Optional character vector of at most 5,000 record IDs. Restricts
  changes before applying `limit`, intersecting any `class` restriction.
  `NULL` selects all IDs;
  [`character()`](https://rdrr.io/r/base/character.html) selects none.
  Duplicate IDs are ignored. Unknown IDs return no rows. This selects
  identities, including delete tombstones, without following references
  or granting access. An empty change result does not prove that the
  selected records exist or that a saved reuse basis is complete.

## Value

A bounded data frame ordered by class and record ID with columns
`class`, `record_id`, `action` (`"insert"` when the record had no
accepted revision at `since`, `"delete"` when its latest revision at
`until` is a deletion, otherwise `"update"`), `revisions` (accepted
revisions inside the window), `changed_fields` (a list-column with the
public fields whose values differ between the record's accepted revision
at `since` and at `until`), and the `revision_id`, `revision_number`,
`batch_id`, `commit_order`, `committed_at`, and public `record`
list-column of the latest revision at `until` (`NULL` for a deletion,
whose `changed_fields` are empty). Only the two boundary revisions of
each changed record are read, so a long revision history does not grow
the result. Attributes `since_commit_order`, `since_batch_id`,
`until_commit_order`, and `until_batch_id` identify the compared
boundaries.

## Details

Each boundary may be a
[`graft_snapshot()`](https://jameshwade.github.io/graft/reference/graft_snapshot.md)
captured from the same store, a committed batch ID, or a scalar `POSIXt`
time. `since` defaults to the store's origin, so every accepted record
is reported as an insert. `until` defaults to the store's current head,
or to the pinned boundary of a `GraftView`; a view rejects any later
boundary.
