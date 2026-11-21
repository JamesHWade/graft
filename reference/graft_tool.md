# Create a fixed read-only ellmer tool for reviewed content

Create an
[ellmer::ToolDef](https://ellmer.tidyverse.org/reference/ToolDef.html)
that reads content accepted for one decision stream and purpose chosen
by the host application. The tool has no model-controlled arguments and
never writes to the store. It evaluates `eligible` on every invocation
before it looks up retained content.

## Usage

``` r
graft_tool(
  store,
  stream,
  purpose,
  eligible,
  name = "recall_project_memory",
  max_text_bytes = 64 * 1024L
)
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

- max_text_bytes:

  Maximum total UTF-8 bytes of text previews returned for one
  invocation. Text beyond this bound is marked as truncated and its
  exact artifact reference is retained. Binary artifacts are always
  represented by reference and byte size only. Defaults to 64 KiB.

## Value

An
[ellmer::ToolDef](https://ellmer.tidyverse.org/reference/ToolDef.html).
Calling the tool returns an
[ellmer::ContentToolResult](https://ellmer.tidyverse.org/reference/Content.html)
whose value is a JSON string.

## Details

The JSON value contains the lookup `status`, fixed `stream` and
`purpose`, and the retained `decision_id`. An accepted result includes
bounded artifact descriptors with `ref`, `data`, `media_type`, `size`,
dependency references, and explicit `truncated` and `omitted` flags. Its
`roots` field contains root references and metadata only; full previews
are in `artifacts`. The top-level `omitted` field retains every omitted
exact reference. The text bound covers UTF-8 artifact previews; retained
reference and status metadata remains subject to the recall limits.
Missing and withdrawn results have distinct messages and no artifact
content.
