# Create bounded read-only tools for a Graft store or view

`graft_tools()` returns
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
definitions that delegate only to Graft's public bounded retrieval
operations. The tools do not expose SQL, filesystem, network,
connection, or mutation arguments. Data-dict stores also expose
[`graft_dictionary()`](https://jameshwade.github.io/graft/reference/graft_dictionary.md)
for public metadata. When the store has accepted definitions,
`graft_definitions` exposes their bounded catalog and one
`graft_calculate` tool composes them through
[`graft_calculate()`](https://jameshwade.github.io/graft/reference/graft_calculate.md).
Both are omitted when no definitions are accepted. When given a
`GraftView`, all tools remain pinned to its immutable snapshot boundary
and the live-store integrity diagnostic is unavailable.

## Usage

``` r
graft_tools(store)
```

## Arguments

- store:

  An initialized `GraftStore` or immutable `GraftView`.

## Value

A named list of
[`ellmer::ToolDef`](https://ellmer.tidyverse.org/reference/ToolDef.html)
objects.

## Details

Every tool returns `result`, `truncated`, `limit`, and one canonical
nested `receipt`. The receipt identifies the store, exact accepted
boundary, and structural and build schema digests. Calculation receipts
also identify the complete accepted definition closure. Live-store tools
pin a fresh boundary for each invocation; tools created from a
`GraftView` retain its snapshot boundary.

## See also

[`vignette("agents", package = "graft")`](https://jameshwade.github.io/graft/articles/agents.md)
for pinning an accepted boundary, registering the tools with a chat, and
accepting agent-authored proposals.
