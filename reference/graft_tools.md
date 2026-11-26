# Create read-only ellmer tools for multi-stream reviewed memory

Create a pair of
[ellmer::ToolDef](https://ellmer.tidyverse.org/reference/ToolDef.html)
tools so an agent can list eligible reviewed streams for one host-chosen
`purpose` and recall any eligible stream on demand. Unlike
[`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md),
the model chooses which stream to recall, but its argument is never
authority by itself: every call checks the host's `streams` allowlist
(when supplied) and evaluates `eligible(stream)` afresh before reading
retained content.

## Usage

``` r
graft_tools(
  store,
  purpose,
  eligible,
  streams = NULL,
  list_name = "list_project_memory",
  recall_name = "recall_project_memory",
  max_streams = 100L,
  max_text_bytes = 64 * 1024L
)
```

## Arguments

- store:

  A store returned by
  [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  or
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md).
  The handle remains private inside the tools.

- purpose:

  The consultation purpose fixed by the host application.

- eligible:

  A required host-supplied one-argument function taking a stream name
  and returning one `TRUE` or `FALSE` value. Evaluated for each
  candidate stream during listing and again on every recall invocation.

- streams:

  Optional host allowlist of stream names: `NULL` to discover accepted
  streams in `store` for `purpose`, a character vector of allowed stream
  names, or a zero-argument function returning a character vector of
  currently allowed stream names.

- list_name:

  Tool name for listing eligible streams. Defaults to
  `"list_project_memory"`.

- recall_name:

  Tool name for recalling one stream. Defaults to
  `"recall_project_memory"`.

- max_streams:

  Maximum eligible accepted streams returned by the listing tool.
  Defaults to `100L`.

- max_text_bytes:

  Maximum total UTF-8 bytes of text previews returned for one recall
  invocation. Defaults to 64 KiB.

## Value

A named list of two
[ellmer::ToolDef](https://ellmer.tidyverse.org/reference/ToolDef.html)
objects (`list_name` and `recall_name`), ready for `chat$set_tools()`,
`deputy::Agent$new()`, or
[`mcptools::mcp_server()`](https://posit-dev.github.io/mcptools/reference/server.html).

## Details

The listing tool returns only streams whose current decision is
`"accept"` for `purpose` and for which `eligible(stream)` returns
`TRUE`. Withdrawn streams, streams for other purposes, ineligible
streams, and total store counts are never disclosed. When `streams` is
supplied, only those stream names are inspected.

The recall tool accepts one `stream` string argument, verifies it
against `streams` (when supplied) and `eligible(stream)`, and returns
the same bounded
[ellmer::ContentToolResult](https://ellmer.tidyverse.org/reference/Content.html),
JSON payload, `@extra$graft` metadata, and optional `shinychat` display
metadata as
[`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md).
A stream not in the host allowlist fails with the same
`graft_ineligible_error` as an ineligible stream.
