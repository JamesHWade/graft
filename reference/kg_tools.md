# Create bounded ellmer tools for a graft store

`kg_tools()` creates six read-only
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
definitions that capture one initialized store. The tools expose only
graft's bounded retrieval functions; they do not accept SQL, file paths,
URLs, or network options.

## Usage

``` r
kg_tools(store)
```

## Arguments

- store:

  An initialized `kg_store`.

## Value

A named list of six
[`ellmer::ToolDef`](https://ellmer.tidyverse.org/reference/tool.html)
objects.

## Details

Every tool returns the native graft result in `result` plus explicit
`truncated`, `limit`, and `store_schema_digest` fields.
