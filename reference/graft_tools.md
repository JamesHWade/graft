# Create bounded read-only tools for a Graft store or view

`graft_tools()` returns four
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
definitions that delegate only to Graft's public bounded retrieval
operations. The tools do not expose SQL, filesystem, network,
connection, or mutation arguments. When given a `GraftView`, all four
tools remain pinned to its immutable snapshot boundary and the
live-store integrity diagnostic is unavailable.

## Usage

``` r
graft_tools(store)
```

## Arguments

- store:

  An initialized `GraftStore` or immutable `GraftView`.

## Value

A named list of four
[`ellmer::ToolDef`](https://ellmer.tidyverse.org/reference/tool.html)
objects.

## Details

Every tool returns `result` plus explicit `truncated`, `limit`, and
`store_schema_digest` metadata.
