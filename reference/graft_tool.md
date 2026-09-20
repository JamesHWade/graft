# Expose reviewed content through a fixed read-only ellmer tool

Create an
[ellmer::ToolDef](https://ellmer.tidyverse.org/reference/ToolDef.html)
that consults one host-selected stream and purpose. The tool has no
model-controlled arguments and never writes to the store. `eligible` is
evaluated for every invocation, before any retained content is looked
up.

## Usage

``` r
graft_tool(store, stream, purpose, eligible, name = "recall_project_memory")
```

## Arguments

- store:

  A store returned by
  [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  or
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md).
  The handle remains private to the tool closure.

- stream:

  A fixed host-owned decision stream.

- purpose:

  The fixed consultation purpose.

- eligible:

  A required no-argument function supplied by the host. It must return
  the current consultation decision when called.

- name:

  The ellmer tool name. Defaults to `"recall_project_memory"`.

## Value

An
[ellmer::ToolDef](https://ellmer.tidyverse.org/reference/ToolDef.html).
Calling the tool returns a native
[ellmer::ContentToolResult](https://ellmer.tidyverse.org/reference/Content.html)
whose value is a JSON string.
