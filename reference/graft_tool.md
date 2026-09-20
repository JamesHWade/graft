# Create a fixed read-only ellmer tool for reviewed content

Create an
[ellmer::ToolDef](https://ellmer.tidyverse.org/reference/ToolDef.html)
that reads content accepted for one decision stream and purpose chosen
by the host application. The tool has no model-controlled arguments and
never writes to the store. It evaluates `eligible` on every invocation
before it looks up retained content.

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
  The handle remains private inside the tool.

- stream:

  A decision stream chosen and controlled by the host application.

- purpose:

  The consultation purpose to use for every invocation.

- eligible:

  A required host-supplied function with no arguments. It must return
  whether the current consultation is allowed when called.

- name:

  The ellmer tool name. Defaults to `"recall_project_memory"`.

## Value

An
[ellmer::ToolDef](https://ellmer.tidyverse.org/reference/ToolDef.html).
Calling the tool returns an
[ellmer::ContentToolResult](https://ellmer.tidyverse.org/reference/Content.html)
whose value is a JSON string.
