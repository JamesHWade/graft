# Package index

## Define and open

Load the domain contract and manage the store that accepts knowledge
under it.

- [`graft_schema()`](https://jameshwade.github.io/graft/reference/graft_schema.md)
  : Load or compile a Graft schema
- [`graft_open()`](https://jameshwade.github.io/graft/reference/graft_open.md)
  : Open and initialize a Graft store
- [`graft_close()`](https://jameshwade.github.io/graft/reference/graft_close.md)
  : Close a Graft store

## Propose and accept

Describe a candidate’s origin, plan the change without writing, and
accept it through one atomic commit path.

- [`graft_provenance()`](https://jameshwade.github.io/graft/reference/graft_provenance.md)
  : Describe the provenance of a candidate knowledge change
- [`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md)
  : Plan a candidate knowledge change without writing it
- [`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md)
  : Commit a reviewed knowledge-change plan
- [`graft_ingest()`](https://jameshwade.github.io/graft/reference/graft_ingest.md)
  : Plan and immediately commit candidate records

## Retrieve and inspect

Read current and historical accepted knowledge through bounded,
contract-aware operations and projections.

- [`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md)
  : Retrieve one current accepted record
- [`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md)
  : Search current accepted records
- [`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md)
  : Run a bounded advanced retrieval operation
- [`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)
  : Retrieve accepted record history

## Synchronize and integrate

Synchronize the readable working tree, review file edits as proposals,
and expose accepted retrieval to agents.

- [`graft_sync()`](https://jameshwade.github.io/graft/reference/graft_sync.md)
  : Synchronize the managed open-knowledge working tree
- [`graft_status()`](https://jameshwade.github.io/graft/reference/graft_status.md)
  : Inspect the managed open-knowledge working tree
- [`graft_review()`](https://jameshwade.github.io/graft/reference/graft_review.md)
  : Review edited open knowledge as a commit plan
- [`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
  : Create bounded read-only tools for a Graft store
