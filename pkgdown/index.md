# graft

<div class="graft-hero">
<p class="graft-eyebrow">Knowledge from ordinary R tables</p>
<h2 data-toc-skip>Turn related tables into knowledge you can update without losing history.</h2>
<p class="graft-hero-copy">
Start with data frames and a data-dict contract. graft creates a new local
store, checks related records before it writes, records where each accepted
change came from, and keeps earlier versions available.
</p>
<div class="graft-actions">
<a class="btn btn-primary" href="articles/getting-started.html">Build your first store</a>
<a class="btn btn-outline-secondary" href="articles/data-dict-schema.html">Start with data-dict</a>
</div>
</div>

## Install graft

graft is currently installed from GitHub:

```r
pak::pak("JamesHWade/graft")
```

Using a resolved data-dict contract and an existing `.graft.json` contract is
R-only. The data-dict CLI is needed only to resolve authored YAML, and Python
with `linkml-runtime` is needed only to compile LinkML source.

## Start with the data you already have

Suppose an R workflow produces three tables:

| Table | What one row represents | Important fields |
|---|---|---|
| `organization` | An organization | `id`, `name` |
| `person` | A person | `id`, `full_name`, `job_title` |
| `employment` | A person's employment | `person_id`, `organization_id` |

Those tables can answer who works where today. They do not, by themselves,
tell you whether an employment row points to a known organization, who supplied
a correction, what a reviewer accepted, or what the previous job title was.

graft adds stable record identity, relationship checks, source provenance, a
review step, and revision history. These are the foundations of useful
knowledge: facts that remain connected and explainable as they change.

## Describe the tables with data-dict

[data-dict](https://data-dict.tidyverse.org/) gives the tables and their
relationships a readable contract. The package includes this example as
`team-directory.data-dict.yaml`; an abridged excerpt of its relationships is:

```yaml
tables:
  - name: person
  - name: organization
  - name: employment

relationships:
  - join: employment.person_id = person.id
  - join: employment.organization_id = organization.id
```

The data-dict CLI resolves the authoring YAML with `export-spec`. A resolved
JSON export can then be compiled by graft using R alone:

```r
library(graft)

resolved_json <- system.file(
  "extdata",
  "team-directory.data-dict.json",
  package = "graft",
  mustWork = TRUE
)

schema <- graft_schema(resolved_json)
schema@name
names(schema@classes)
```

The `@` operator reads a public property from graft's immutable S7 contract and
plan objects; candidate records themselves remain ordinary data frames.

The full [data-dict guide](articles/data-dict-schema.html) shows how to author,
resolve, and inspect the contract. The [compiler
reference](articles/contract-compilers.html) documents the exact supported
profiles and build requirements.

## Create a new, empty store

You do not need an existing database. The path below does not exist when
`graft_open()` is called; graft creates and initializes it under the compiled
contract.

```r
store_path <- tempfile(fileext = ".duckdb")
file.exists(store_path)
#> [1] FALSE

store <- graft_open(schema, store_path, okf = "disabled")
```

Use `":memory:"` instead of a file path for a disposable in-memory store.

## Catch a broken relationship before writing

Candidate records are a named list of data frames. This batch includes a valid
person and organization, but its employment row points to an organization that
does not exist.

```r
records <- list(
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
    organization_id = "org:missing"
  )
)

origin <- graft_provenance(
  producer = "directory-import",
  idempotency_key = "directory-2026-08-09"
)

plan <- graft_plan(store, records, origin)
plan@valid
#> [1] FALSE

plan@issues[, c("class", "record_id", "field", "message")]
```

The issue reports that `org:missing` is not a known target. Planning has not
written any records or provenance, so the caller can correct the batch and
review it again.

## Correct, review, and commit the batch

```r
records$employment$organization_id <- "org:daily-planet"
plan <- graft_plan(store, records, origin)

plan@valid
plan@changes[, c("class", "record_id", "action", "changed_fields")]

if (plan@valid) {
  graft_commit(store, plan)
}
```

The plan now shows three inserts. `graft_commit()` rechecks the reviewed plan
and accepts all three records together. If a precondition fails, none of the
batch is accepted.

## Keep the old version when a fact changes

A later review changes Lois's role. The update plan identifies the field that
would change before anything is written.

```r
updated_person <- list(person = data.frame(
  id = "person:lois-lane",
  full_name = "Lois Lane",
  job_title = "Investigative editor"
))

update_origin <- graft_provenance(
  producer = "hr-review",
  idempotency_key = "hr-review-2026-08-10"
)

update_plan <- graft_plan(store, updated_person, update_origin)
update_plan@changes[, c("record_id", "action", "changed_fields")]
graft_commit(store, update_plan)

graft_get(store, "person:lois-lane")$record
graft_history(store, "person:lois-lane")[
  , c("revision_number", "committed_at", "producer", "changed_fields")
]

graft_close(store)
unlink(store_path)
```

Current retrieval returns the new title. History retains both accepted
versions and the producer attached to each change.

## Add LinkML when the relationships need graph meaning

data-dict is the simpler starting point when the domain is naturally tabular.
Its foreign keys let graft reject missing targets, but they are not graph
traversal edges. Move to [LinkML](articles/linkml-schema.html) when you need
relationships that support graph traversal, inheritance, ontology identifiers,
or polymorphic references.

Both providers compile to the same Graft contract and use the same plan,
commit, retrieval, and history functions. The provider changes how the domain
is described; it does not create another way to write accepted knowledge.
The evaluated LinkML guide accepts a semantic measurement and retrieves the
typed `materials:testedWith` edge between two materials.

## Continue learning

- [Get started](articles/getting-started.html) works through the complete
  data-dict example with its results.
- [Use a data-dict contract](articles/data-dict-schema.html) covers table-first
  authoring and compilation.
- [Review knowledge changes](articles/knowledge-change-control.html) explains
  plans, commit preconditions, and retries.
- [Retrieve current records and history](articles/retrieval.html) maps each read
  function to its job.
- [Add graph semantics with LinkML](articles/linkml-schema.html) continues from
  governed tables to typed traversal relationships.
- [Understand the architecture](articles/architecture.html) explains storage,
  projections, and selective use of S7.
