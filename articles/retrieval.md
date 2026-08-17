# Retrieve accepted knowledge

Graft provides four read operations:
[`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md),
[`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md),
[`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md),
and
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md).
[`graft_snapshot()`](https://jameshwade.github.io/graft/reference/graft_snapshot.md)
captures an accepted boundary, and
[`graft_at()`](https://jameshwade.github.io/graft/reference/graft_at.md)
binds it to a read-only view that those operations can use.
[`graft_view_snapshot()`](https://jameshwade.github.io/graft/reference/graft_view_snapshot.md)
recovers the exact path-free boundary retained by a view.
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)
uses the exact contract recorded for each revision. None exposes raw SQL
or a mutation path.

| Need | Function | Result |
|----|----|----|
| One current record | [`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md) | The record and its accepted context |
| Search public fields | [`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md) | Ranked, bounded matches |
| A fixed advanced operation | [`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md) | A validated operation-specific result |
| Accepted revisions | [`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md) | Newest-first immutable history |
| A pinned accepted boundary | [`graft_snapshot()`](https://jameshwade.github.io/graft/reference/graft_snapshot.md), [`graft_at()`](https://jameshwade.github.io/graft/reference/graft_at.md) | A serializable reference and live read view |
| A view’s retained boundary | [`graft_view_snapshot()`](https://jameshwade.github.io/graft/reference/graft_view_snapshot.md) | An isolated copy of the exact pinned snapshot |
| Read-only agent access | [`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md) | Tool definitions backed by the same reads |

## Create some accepted knowledge

This example uses the resolved data-dict contract included with Graft.
It describes people, organizations, and employment records that refer to
both. The foreign keys are checked during planning, but they are not
semantic graph edges.

``` r

library(graft)

schema <- graft_schema(system.file(
  "extdata",
  "team-directory.data-dict.json",
  package = "graft",
  mustWork = TRUE
))
store <- graft_open(schema, ":memory:", okf = "disabled")

graft_ingest(
  store,
  list(
    organization = data.frame(
      id = "org:daily-planet",
      name = "Daily Planet"
    ),
    person = data.frame(
      id = "person:lois-lane",
      full_name = "Lois Lane",
      job_title = "Reporter"
    ),
    employment = data.frame(
      id = "employment:lois-lane:daily-planet",
      person_id = "person:lois-lane",
      organization_id = "org:daily-planet"
    )
  ),
  graft_provenance(
    producer = "team-directory-import",
    idempotency_key = "team-directory-v1"
  )
)
```

## Pin the accepted boundary

Capture a serializable reference before starting work that must use
fixed accepted knowledge. The reference contains store, schema, and
commit identity, not a filesystem path or live connection.
[`graft_at()`](https://jameshwade.github.io/graft/reference/graft_at.md)
binds it to the open store as a read-only view:

``` r

snapshot <- graft_snapshot(store)
view <- graft_at(store, snapshot)
retained_snapshot <- graft_view_snapshot(view)
```

`retained_snapshot` has the same identity as `snapshot` and remains
path-free. Later commits do not change it or reads through `view`.

## Get one current record

Use
[`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md)
when the stable identifier is already known:

``` r

person <- graft_get(store, "person:lois-lane")
person$record
```

The result includes its class and accepted context. A missing identifier
raises a typed package error; callers do not need to know how the record
is stored internally.

## Find records by public text

Use
[`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md)
when you know a name or phrase rather than an identifier:

``` r

graft_find(store, "Lois", class = "person", limit = 10)
graft_find(store, "Daily", class = "organization", limit = 10)
```

The compiled contract determines which fields are searchable and which
are sensitive. An optional class restriction narrows the search; every
call remains bounded by its result limit.

## Recover accepted history

Accept a later version of the same person:

``` r

graft_ingest(
  store,
  list(
    person = data.frame(
      id = "person:lois-lane",
      full_name = "Lois Lane",
      job_title = "Investigative reporter"
    )
  ),
  graft_provenance(
    producer = "team-directory-import",
    idempotency_key = "team-directory-v2"
  )
)
```

The live store now returns the update, while the view remains at the
accepted boundary captured above:

``` r

graft_get(store, "person:lois-lane")$record$job_title
graft_get(view, "person:lois-lane")$record$job_title
```

[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)
returns the accepted revisions in newest-first order:

``` r

history <- graft_history(
  store,
  id = "person:lois-lane",
  limit = 100
)

history[, c("batch_id", "changed_fields", "record")]
```

An accepted batch ID or `POSIXt` value selects state at an exact commit
boundary. Commit order, rather than a timestamp inside the domain
record, defines that boundary.

## Use fixed advanced operations

[`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md)
accepts named operations with validated request shapes. For example, the
integrity operation checks the revision chain and, when requested, its
derived projections:

``` r

graft_query(
  store,
  operation = "integrity",
  request = list(projections = TRUE),
  limit = 100
)
```

The `neighbors` operation returns semantic edges only when the active
contract declares graph-producing semantic statements or edges. Graft
does not turn the team directory’s data-dict foreign keys, or an
ordinary LinkML object-reference slot, into traversal edges. See [Add
graph semantics with
LinkML](https://jameshwade.github.io/graft/articles/linkml-schema.md)
for that contract shape.

Other fixed operations cover exact identifiers, claims, evidence,
unresolved mentions, and bounded neighbors where the contract supports
them. Unknown request members, unbounded traversal, and arbitrary SQL
are rejected.

## Give agents the same bounded reads

``` r

tools <- graft_tools(view)
names(tools)
```

The definitions call
[`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md),
[`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md),
[`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md),
and
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)
through the captured view, so later commits cannot change their results.
They expose no write operation, raw database connection, filesystem
access, or network access. The host decides which provider receives them
and remains responsible for tool authorization.

Every operation reports its applicable limits and truncation state so a
host can distinguish a complete result from a bounded prefix.

``` r

graft_close(store)
```

Read [Change
control](https://jameshwade.github.io/graft/articles/knowledge-change-control.md)
for the path from proposal to accepted revision and
[Architecture](https://jameshwade.github.io/graft/articles/architecture.md)
for how the ledger and derived views fit together.
