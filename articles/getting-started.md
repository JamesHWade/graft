# Get started with graft

Most projects do not begin with a knowledge store. They begin with
tables: a directory of people, a list of organizations, and a table that
connects them. This guide starts there. It creates an empty in-memory
store, rejects a broken relationship before writing anything, accepts
corrected records, preserves a later update as a second revision, and
then hands that accepted knowledge to an agent as read-only tools.

That last step is the point of the earlier ones. An agent is only as
trustworthy as the knowledge it reads: validated on the way in,
attributed to a producer, and stable while the agent is reasoning about
it. Graft is built to give a model exactly that, and nothing more.

## Load a table contract

The package includes a small team-directory contract written with
[data-dict](https://data-dict.tidyverse.org/). This guide uses its
resolved JSON form, so the runnable lesson needs only R and graft. In a
real authoring workflow, write the YAML, validate it with the data-dict
CLI, and run `data-dict export-spec` once. The human-authored YAML is
included beside the resolved file.

``` r

library(graft)

dictionary_path <- system.file(
  "extdata",
  "team-directory.data-dict.json",
  package = "graft",
  mustWork = TRUE
)

schema <- graft_schema(dictionary_path)

schema@name
#> [1] "team_directory"
names(schema@classes)
#> [1] "organization"    "person"          "employment"      "GraftDefinition"
```

The three class names are the three table names: `organization`,
`person`, and `employment`. The contract defines required columns,
stable string IDs, and the two foreign keys in `employment`. IDs are
strings chosen by the caller and must be globally unique within the
store; the `person:` and `org:` prefixes are readable conventions used
by this example. The `@` operator reads public properties from graft’s
immutable S7 contract and plan objects.

## Create an empty store

[`graft_open()`](https://jameshwade.github.io/graft/reference/graft_open.md)
creates and initializes the database when it does not already exist.
Here the database lives only in memory and starts with no accepted
records.

``` r

store <- graft_open(
  schema,
  path = ":memory:",
  okf = "disabled"
)
```

Use a DuckDB filename instead of `":memory:"` when the knowledge should
persist between R sessions. `okf = "disabled"` leaves the optional
readable file projection off so this first lesson stays focused on the
store and its history.

## Catch a missing relationship before writing

Suppose an import contains Lois Lane and an employment row, but the
referenced organization is absent.

``` r

invalid_records <- list(
  person = data.frame(
    id = "person:lois-lane",
    full_name = "Lois Lane",
    job_title = "Reporter"
  ),
  employment = data.frame(
    id = "employment:lois-lane:daily-planet",
    person_id = "person:lois-lane",
    organization_id = "org:missing"
  )
)

invalid_plan <- graft_plan(
  store,
  invalid_records,
  graft_provenance(
    producer = "directory-import",
    idempotency_key = "directory-invalid"
  )
)

invalid_plan@valid
#> [1] FALSE
invalid_plan@issues[
  , c("class", "field", "rule", "message"),
  drop = FALSE
]
#>        class           field             rule
#> 1 employment organization_id reference_exists
#>                                          message
#> 1 Reference target `org:missing` does not exist.
```

Planning is read-only. The missing organization appears as a review
issue, and neither the person nor the employment row has been accepted.
`producer` names the source workflow. An `idempotency_key` names one
retryable source event so repeating the same accepted event does not
create another revision.

## Correct and review the candidate set

Add the organization and plan all three tables together. These are
ordinary data frames; the list names tell graft which contract table
each frame uses.

``` r

organizations <- data.frame(
  id = "org:daily-planet",
  name = "Daily Planet"
)

people <- data.frame(
  id = "person:lois-lane",
  full_name = "Lois Lane",
  job_title = "Reporter"
)

employment <- data.frame(
  id = "employment:lois-lane:daily-planet",
  person_id = "person:lois-lane",
  organization_id = "org:daily-planet"
)

initial_records <- list(
  organization = organizations,
  person = people,
  employment = employment
)

initial_plan <- graft_plan(
  store,
  initial_records,
  graft_provenance(
    producer = "directory-import",
    run_id = "import-2026-08-01",
    idempotency_key = "directory-2026-08-01"
  )
)

initial_plan@changes[
  , c("class", "record_id", "action"),
  drop = FALSE
]
#>          class                         record_id action
#> 1 organization                  org:daily-planet insert
#> 2       person                  person:lois-lane insert
#> 3   employment employment:lois-lane:daily-planet insert
initial_plan@issues
#> [1] class           input_row       record_id       field          
#> [5] rule            message         condition_class
#> <0 rows> (or 0-length row.names)
```

The organization can satisfy the employment foreign key in the same
candidate set. `@valid` means the plan can be committed; `@changes`
shows whether it should be.

## Commit the reviewed plan

``` r

stopifnot(initial_plan@valid)

initial_result <- graft_commit(store, initial_plan)
initial_result$inserted
#> organization       person   employment 
#>            1            1            1
```

Immediately before writing, graft checks that the plan is intact and
still matches the store and active contract. All three records and their
provenance commit in one transaction.

## Accept a later update

The next directory import changes only Lois’s job title. Planning
compares the candidate with the accepted head and reports one update.

``` r

update_plan <- graft_plan(
  store,
  list(
    person = data.frame(
      id = "person:lois-lane",
      full_name = "Lois Lane",
      job_title = "Investigative editor"
    )
  ),
  graft_provenance(
    producer = "hr-review",
    run_id = "review-2026-08-08",
    idempotency_key = "hr-review-2026-08-08"
  )
)

update_plan@changes[
  , c("class", "record_id", "action", "changed_fields"),
  drop = FALSE
]
#>    class        record_id action changed_fields
#> 1 person person:lois-lane update      job_title

stopifnot(update_plan@valid)
update_result <- graft_commit(store, update_plan)
update_result$updated
#> person 
#>      1
```

## Read current knowledge and history

[`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md)
returns the current accepted record. The employment record keeps the
stable IDs that connect the person to the organization.

``` r

current_person <- graft_get(
  store,
  "person:lois-lane",
  include = character()
)
current_person$record
#> $id
#> [1] "person:lois-lane"
#> 
#> $full_name
#> [1] "Lois Lane"
#> 
#> $job_title
#> [1] "Investigative editor"

current_employment <- graft_get(
  store,
  "employment:lois-lane:daily-planet",
  include = character()
)$record

current_organization <- graft_get(
  store,
  current_employment$organization_id,
  include = character()
)$record
current_organization
#> $id
#> [1] "org:daily-planet"
#> 
#> $name
#> [1] "Daily Planet"
```

[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)
retains both accepted versions. It returns newest first.

``` r

history <- graft_history(store, "person:lois-lane", limit = 10L)

data.frame(
  revision = history$revision_number,
  committed_at = history$committed_at,
  producer = history$producer,
  event = history$source_run_id,
  contract = substr(history$schema_build_digest, 1L, 19L),
  job_title = vapply(
    history$record,
    \(record) record$job_title,
    character(1)
  )
)
#>   revision        committed_at         producer             event
#> 1        2 2026-08-28 17:55:44        hr-review review-2026-08-08
#> 2        1 2026-08-28 17:55:43 directory-import import-2026-08-01
#>              contract            job_title
#> 1 sha256:82fef61f109a Investigative editor
#> 2 sha256:82fef61f109a             Reporter
```

The current record is convenient for applications. The revision history
is the audit trail: it retains what was accepted, when, under which
contract, and from which producer event. The displayed contract value is
an abbreviated build digest; the history result retains the complete
digest.

## Hand the same knowledge to an agent

Everything above was written for a person at the console. The same
accepted knowledge is also what you want an agent to read, and graft
exposes it without handing over a database connection.

First pin the boundary.
[`graft_snapshot()`](https://jameshwade.github.io/graft/reference/graft_snapshot.md)
records the accepted state as a serializable value that holds no
connection and no filesystem path, and
[`graft_at()`](https://jameshwade.github.io/graft/reference/graft_at.md)
binds it to a read-only view:

``` r

snapshot <- graft_snapshot(store)
view <- graft_at(store, snapshot)
```

[`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
then turns that view into four [ellmer](https://ellmer.tidyverse.org/)
tool definitions backed by graft’s public read functions:

``` r

tools <- graft_tools(view)
names(tools)
#> [1] "graft_find"    "graft_get"     "graft_query"   "graft_history"
```

The tools are
[`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md),
[`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md),
[`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md),
and
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)
— search, retrieval, bounded advanced operations, and revision history.
They accept no SQL, no connection, no path, and no write argument, so a
model can read accepted knowledge and cannot alter it or reach past it.

Each call returns its result together with the limit it applied, whether
the result was truncated, and the digest of the contract it came from:

``` r

found <- tools$graft_find(query = "Lois", class = "person", limit = 5)

found$truncated
#> [1] FALSE
found$limit
#> [1] 5
found$result[, c("id", "class", "label")]
#>                 id  class     label
#> 1 person:lois-lane person Lois Lane
```

A model that received only part of an answer is told so, instead of
reasoning over a silent prefix. Because these tools are bound to `view`,
later commits do not move the ground underneath a running session; a
second run against the same snapshot reads the same knowledge.

Registering them with a chat is one line:

``` r

chat <- ellmer::chat_anthropic()
chat$set_tools(tools)

chat$chat("Who works at the Daily Planet, and has that person's title changed?")
```

The agent answers from accepted records and can cite the revision
history behind them. When an agent should also propose records — and be
recorded as the producer that did — read [Work with
agents](https://jameshwade.github.io/graft/articles/agents.md).

## Close the store

``` r

graft_close(store)
```

## Add richer graph meaning with LinkML

The data-dict contract was enough to validate ordinary tables and their
scalar foreign keys. Those foreign keys remain validated references;
graft does not turn them into graph traversal edges.

LinkML is the next step when a relationship needs ontology identifiers,
inheritance, polymorphic targets, or explicit semantic statement and
evidence shapes. The bundled materials contract declares `Measurement`
as a semantic statement, so accepted entity-valued measurements can
become typed traversal edges. This is deliberately a second domain: the
LinkML guide first explains how the same team-directory concepts map to
LinkML, then uses materials to run a semantic edge that the package
already ships.

``` r

linkml_schema <- graft_schema(system.file(
  "extdata",
  "materials.graft.json",
  package = "graft",
  mustWork = TRUE
))

linkml_schema@classes$Measurement@role
#> [1] "statement"
linkml_schema@classes$Measurement@statement_shape
#> [1] "semantic"
```

Read [the data-dict
guide](https://jameshwade.github.io/graft/articles/data-dict-schema.md)
to adapt an existing table contract. Next, deepen the package workflow
with [change
control](https://jameshwade.github.io/graft/articles/knowledge-change-control.md)
and [retrieval and
history](https://jameshwade.github.io/graft/articles/retrieval.md). Read
[Work with
agents](https://jameshwade.github.io/graft/articles/agents.md) to give a
model bounded reads and a reviewed proposal path. Then read the [LinkML
guide](https://jameshwade.github.io/graft/articles/linkml-schema.md)
when the domain needs richer semantic structure.
