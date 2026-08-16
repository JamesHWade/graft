# Get started with graft

Most projects do not begin with a knowledge store. They begin with
tables: a directory of people, a list of organizations, and a table that
connects them. This guide starts there. It creates an empty in-memory
store, rejects a broken relationship before writing anything, accepts
corrected records, and preserves a later update as a second revision.

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
#> [1] "organization" "person"       "employment"
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
#> 1        2 2026-08-16 00:03:27        hr-review review-2026-08-08
#> 2        1 2026-08-16 00:03:26 directory-import import-2026-08-01
#>              contract            job_title
#> 1 sha256:d3444e6482b8 Investigative editor
#> 2 sha256:d3444e6482b8             Reporter
```

The current record is convenient for applications. The revision history
is the audit trail: it retains what was accepted, when, under which
contract, and from which producer event. The displayed contract value is
an abbreviated build digest; the history result retains the complete
digest.

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
history](https://jameshwade.github.io/graft/articles/retrieval.md). Then
read the [LinkML
guide](https://jameshwade.github.io/graft/articles/linkml-schema.md)
when the domain needs richer semantic structure.
