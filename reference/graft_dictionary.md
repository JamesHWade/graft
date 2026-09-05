# Discover the public data dictionary at an accepted boundary

`graft_dictionary()` exposes the accepted data-dict contract without
record values, examples, observed ranges, source locators, or restricted
columns. Public descriptive prose is not content-scrubbed; authors must
keep private information out of public descriptions and glossary
entries.

## Usage

``` r
graft_dictionary(source, table = NULL, field = NULL, limit = 100L, offset = 0L)
```

## Arguments

- source:

  An initialized `GraftStore` or immutable `GraftView` with a data-dict
  contract. Views retain their historical contract and receipt.

- table:

  Optional dictionary table name.

- field:

  Optional public column name; requires `table`.

- limit:

  Maximum entries to return, from 1 to 100.

- offset:

  Number of entries to skip, from 0 to 1,000,000.

## Value

A list with `result`, `truncated`, `limit`, and a canonical `receipt`.
`result` contains an `entries` data frame, `total`, and `next_offset`
(`NULL` on the last page). Entries have `kind`, `table`, `field`,
`name`, `value`, `semantics`, and `text_truncated` columns. Compound
values are JSON.

## Details

Entries follow document order, then adapter semantics. Each string cell
is capped at 2,000 characters. `text_truncated` marks clipped rows, and
the outer `truncated` flag also reports remaining pages. Narrow the
selection or use `next_offset` to retrieve another page. Selection uses
dictionary names. Dataset and glossary context is included with every
selection; table and column context is scoped. Relationships are
included only when all endpoints are public and at least one endpoint
matches the selection. Only resolved endpoint pairs and cardinality are
shown: pairs do not encode join operators or aliases, so discovery does
not reconstruct a join expression. Assertions require resolved public
column references; dataset assertions and assertions without resolved
references are omitted.

`supported` entries describe enforced contract properties. `descriptive`
entries are metadata, not executable assertions or acceptance
constraints. `unsupported` entries explain semantics outside Graft's
supported profile. Discovery is a generic read for
[`graft_verify()`](https://jameshwade.github.io/graft/reference/graft_verify.md):
an explicit matching quotation is required for cited evidence, and it is
never calculation evidence.
