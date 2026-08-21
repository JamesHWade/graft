# Package index

## Define and open

Compile or load a contract, then create, open, and close a store.

- [`graft_schema()`](https://jameshwade.github.io/graft/reference/graft_schema.md)
  : Load or compile a Graft schema
- [`graft_open()`](https://jameshwade.github.io/graft/reference/graft_open.md)
  : Open and initialize a Graft store
- [`graft_close()`](https://jameshwade.github.io/graft/reference/graft_close.md)
  : Close a Graft store

## Propose and accept

Record where candidates came from, inspect a plan, and commit it.

- [`graft_provenance()`](https://jameshwade.github.io/graft/reference/graft_provenance.md)
  : Describe the provenance of a candidate knowledge change
- [`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md)
  : Plan a candidate knowledge change without writing it
- [`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md)
  : Commit a reviewed knowledge-change plan
- [`graft_ingest()`](https://jameshwade.github.io/graft/reference/graft_ingest.md)
  : Plan and immediately commit candidate records

## Retrieve and inspect

Pin an accepted boundary, then read records, search results, fixed
projections, and history.

- [`graft_snapshot()`](https://jameshwade.github.io/graft/reference/graft_snapshot.md)
  : Capture an immutable knowledge snapshot
- [`graft_at()`](https://jameshwade.github.io/graft/reference/graft_at.md)
  : Open an immutable read view
- [`graft_view_snapshot()`](https://jameshwade.github.io/graft/reference/graft_view_snapshot.md)
  : Recover the immutable snapshot retained by a view
- [`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md)
  : Retrieve one current accepted record
- [`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md)
  : Search current accepted records
- [`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md)
  : Run a bounded advanced retrieval operation
- [`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)
  : Retrieve accepted record history

## Synchronize and integrate

Synchronize readable files, review file edits, and provide bounded
read-only tools to an agent host.

- [`graft_sync()`](https://jameshwade.github.io/graft/reference/graft_sync.md)
  : Synchronize the managed open-knowledge working tree
- [`graft_status()`](https://jameshwade.github.io/graft/reference/graft_status.md)
  : Inspect the managed open-knowledge working tree
- [`graft_review()`](https://jameshwade.github.io/graft/reference/graft_review.md)
  : Review edited open knowledge as a commit plan
- [`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
  : Create bounded read-only tools for a Graft store or view
