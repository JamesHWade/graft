# Retrieve accepted knowledge

graft’s read surface is deliberately smaller than its storage model.
Four functions cover current records, search, fixed advanced operations,
and immutable history.
[`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
exposes the same accepted reads to an agent host without adding mutation
or raw SQL.

| Need | Function | Result |
|----|----|----|
| One current record | [`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md) | A hydrated record and its accepted context |
| Search public fields | [`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md) | Ranked, bounded matches |
| A fixed advanced shape | [`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md) | A validated operation-specific result |
| Accepted revisions | [`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md) | Newest-first immutable history |
| Read-only agent access | [`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md) | Tool definitions backed by the four reads |

All reads are governed by the active contract and accepted revision
ledger. Internal projections make them efficient, but projections are
not independent sources of knowledge.

## Create a small accepted graph

``` r

library(graft)

schema <- graft_schema(system.file(
  "extdata",
  "personinfo.graft.json",
  package = "graft"
))
store <- graft_open(schema, ":memory:", okf = "disabled")

graft_ingest(
  store,
  list(
    Organization = data.frame(
      id = "org:daily-planet",
      name = "Daily Planet"
    ),
    Person = data.frame(
      id = "person:clark-kent",
      full_name = "Clark Kent",
      aliases = I(list(c("Superman", "Kal-El"))),
      employed_by = I(list("org:daily-planet"))
    )
  ),
  graft_provenance(
    producer = "directory-import",
    idempotency_key = "daily-planet-v1"
  )
)
```

## Get one current record

Use
[`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md)
when the stable identifier is already known:

``` r

person <- graft_get(store, "person:clark-kent")
person$record
```

The result includes accepted context rather than returning an
unqualified storage row. Missing identifiers return a typed package
error; callers do not need to know which projection table serves the
request.

## Find records by public text

Use
[`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md)
for human-facing lookup across public search fields declared by the
active compiled contract:

``` r

graft_find(store, "Clark", class = "Person", limit = 10)
graft_find(store, "Daily", class = "Organization", limit = 10)
```

Class and limit are explicit. Sensitive fields are excluded by contract
rather than filtered by the caller after retrieval.

## Query a fixed advanced operation

[`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md)
is the extension point for reads that need a richer shape. The operation
chooses a validated request schema; the request supplies only values for
that operation.

``` r

graft_query(
  store,
  operation = "neighbors",
  request = list(
    id = "person:clark-kent",
    projection = "semantic",
    hops = 1,
    max_nodes = 25,
    max_edges = 50
  )
)
```

Operations cover exact identifiers, identifiers, claims, evidence,
bounded neighbors, unresolved mentions, and integrity. Unknown request
members, unbounded traversal, and arbitrary SQL are rejected.

Use the integrity operation when diagnosing the accepted ledger or
derived views:

``` r

graft_query(
  store,
  operation = "integrity",
  request = list(projections = TRUE),
  limit = 100
)
```

Projection drift is repairable from accepted revisions. A successful
current query is not treated as proof that the historical chain is
intact; integrity inspection checks the authoritative chain directly.

## Recover immutable history

Use
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)
when the question includes “when,” “why,” or “what changed”:

``` r

history <- graft_history(
  store,
  id = "person:clark-kent",
  limit = 100
)

history[, c("batch_id", "changed_fields", "record")]
```

An accepted batch ID or `POSIXt` value selects state at an exact commit
boundary. Commit order, not a domain record’s timestamp, defines
historical boundaries.

## Give agents the same bounded reads

``` r

tools <- graft_tools(store)
names(tools)
```

The returned definitions are backed by
[`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md),
[`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md),
[`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md),
and
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md).
They expose no write operation, raw database connection, filesystem
access, or network access. The host decides which provider receives them
and remains responsible for tool authorization.

Every operation reports its applicable limits and truncation state so a
host can distinguish “complete result” from “bounded prefix.”

``` r

graft_close(store)
```

Read
[Architecture](https://jameshwade.github.io/graft/articles/architecture.md)
for the ledger/projection boundary and [Change
control](https://jameshwade.github.io/graft/articles/knowledge-change-control.md)
for how a record becomes part of the accepted view.
