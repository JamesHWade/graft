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
- [`graft_proposal_type()`](https://jameshwade.github.io/graft/reference/graft_proposal_type.md)
  : Derive a structured proposal type from the accepted dictionary
- [`graft_proposal_plan()`](https://jameshwade.github.io/graft/reference/graft_proposal_plan.md)
  : Turn raw structured proposals into a reviewable plan
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
- [`graft_changes()`](https://jameshwade.github.io/graft/reference/graft_changes.md)
  : List accepted changes between two boundaries
- [`graft_dictionary()`](https://jameshwade.github.io/graft/reference/graft_dictionary.md)
  : Discover the public data dictionary at an accepted boundary
- [`graft_definitions()`](https://jameshwade.github.io/graft/reference/graft_definitions.md)
  : List accepted definitions
- [`graft_calculate()`](https://jameshwade.github.io/graft/reference/graft_calculate.md)
  : Evaluate accepted definitions

## Synchronize and integrate

Synchronize readable files, review file edits, and provide bounded
read-only tools to an agent host, then verify its recorded evidence.

- [`graft_sync()`](https://jameshwade.github.io/graft/reference/graft_sync.md)
  : Synchronize the managed open-knowledge working tree
- [`graft_status()`](https://jameshwade.github.io/graft/reference/graft_status.md)
  : Inspect the managed open-knowledge working tree
- [`graft_review()`](https://jameshwade.github.io/graft/reference/graft_review.md)
  : Review edited open knowledge as a commit plan
- [`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
  : Create bounded read-only tools for a Graft store or view
- [`graft_verify()`](https://jameshwade.github.io/graft/reference/graft_verify.md)
  : Verify recorded Graft evidence for assistant answers
- [`graft_commons_data_source()`](https://jameshwade.github.io/graft/reference/graft_commons_data_source.md)
  : Create a detached Commons data source
- [`graft_contract_version()`](https://jameshwade.github.io/graft/reference/graft_contract_version.md)
  : Report the Graft consumer contract version
