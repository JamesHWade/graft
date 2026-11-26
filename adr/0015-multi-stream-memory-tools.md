# ADR 0015: Bounded multi-stream discovery and recall tools

Status: Accepted for implementation in #111. Extends ADR 0014's single-stream
tool boundary.

## Context

`graft_tool()` fixes a single decision stream at construction. Applications
with more than one reviewed topic—such as a team metrics notebook, a research
library, or a local MCP server—need an agent to discover which reviewed topics
exist and recall one on demand without building a bespoke catalog or weakening
per-call authorization.

## Decision

Add `graft_tools(store, purpose, eligible, streams = NULL, ...)` returning a
named list of two read-only `ellmer::ToolDef` tools: a listing tool
(`list_project_memory` by default) and a parameterized recall tool
(`recall_project_memory` by default). Keep `graft_tool()` unchanged for
single-stream use.

1. **Model selection is never authority.** The recall tool accepts a single
   `stream` string argument, but checks it against the host's allowed stream
   set (when supplied via `streams`) and invokes `eligible(stream)` afresh on
   every call. A stream outside the host allowlist fails with the same
   `graft_ineligible_error` class and message as an ineligible stream so the
   model cannot probe for hidden streams.
2. **One per-stream eligibility callback.** `eligible` is a one-argument
   function `function(stream)` returning a scalar boolean. It runs for each
   stream during listing and again on every recall invocation.
3. **Listings reveal only eligible accepted streams.** The listing tool returns
   only streams whose current decision is `accept` for the fixed `purpose` and
   for which `eligible(stream)` returns `TRUE`. Withdrawn streams, other
   purposes, ineligible streams, and total store stream counts are omitted.
   When `streams` is supplied as an explicit allowlist (character vector or
   zero-argument function), listing inspects only those streams rather than
   enumerating the store.
4. **Same bounds and metadata.** Multi-stream recall shares the exact UTF-8
   `max_text_bytes` bounds, `@extra$graft` consultation metadata, and
   `shinychat` display metadata as `graft_tool()`. Both tools are annotated
   read-only, closed-world, idempotent, and non-destructive.
5. **Search stays external.** Semantic search belongs in retrieval layers such
   as `ragnar`. Applications index currently accepted selections keyed by exact
   stream and artifact revision, update or remove entries on correction or
   withdrawal, and always pass search hits through `graft_recall()` before use.

## Consequences

- Agents and MCP clients can navigate a multi-topic project memory store with
  one `graft_tools()` call while preserving host authorization on every read.
- Applications using `ragnar` get a clear composition seam: `ragnar` finds
  candidate streams, and `graft_recall()` verifies current acceptance before
  content reaches the model.
