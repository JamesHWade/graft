# Read accepted knowledge from the managed OKF working tree

`kg_okf_context()` gives people and agents a bounded, progressively
disclosed view of current accepted knowledge. With no filters it returns
a concept index. Supplying `query` or `types` includes matching Markdown
documents. Modified, stale, or incompatible bundles are refused because
they are proposals rather than accepted knowledge. Reads use a verified
filesystem snapshot and refuse bundles above the hard agent-context byte
limit.

## Usage

``` r
kg_okf_context(
  store,
  query = NULL,
  types = NULL,
  limit = 25,
  max_chars = 50000,
  path = NULL
)
```

## Arguments

- store:

  An initialized `kg_store`.

- query:

  Optional case-insensitive text query.

- types:

  Optional OKF concept types.

- limit:

  Maximum number of matching concepts.

- max_chars:

  Maximum characters in the rendered context.

- path:

  Optional bundle directory. The default uses the managed path.

## Value

A `kg_okf_context` object.
