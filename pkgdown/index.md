# graft

<div class="graft-hero">
<p class="graft-eyebrow">Knowledge from ordinary R tables</p>
<h2 data-toc-skip>Turn related tables into knowledge you can update without losing history.</h2>
<p class="graft-hero-copy">
Start with data frames and a data-dict contract. graft creates a new local
store, checks related records before it writes, records where each accepted
change came from, and keeps earlier versions available &mdash; then hands that
accepted knowledge to an agent as bounded, read-only tools.
</p>
<div class="graft-actions">
<a class="btn btn-primary" href="articles/getting-started.html">Build your first store</a>
<a class="btn btn-outline-secondary" href="articles/agents.html">Work with agents</a>
</div>
</div>

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
knowledge: facts that remain connected and explainable as they change. They are
also what makes accepted knowledge safe to put in front of a model.

## Install graft

graft is currently installed from GitHub:

```r
pak::pak("JamesHWade/graft")
```

Using a resolved data-dict contract and an existing `.graft.json` contract is
R-only. The data-dict CLI is needed only to resolve authored YAML, and Python
with `linkml-runtime` is needed only to compile LinkML source.

## Describe the tables with a contract

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

The data-dict CLI resolves authoring YAML with `export-spec` once. graft
compiles the resolved JSON using R alone, then creates the store — no existing
database required:

```r
library(graft)

schema <- graft_schema(system.file(
  "extdata",
  "team-directory.data-dict.json",
  package = "graft",
  mustWork = TRUE
))

store <- graft_open(schema, tempfile(fileext = ".duckdb"), okf = "disabled")
```

## Review each change before it is written

Candidate records are ordinary data frames. This batch has a valid person and
organization, but its employment row points to an organization that does not
exist:

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
#>        class                         record_id           field                                        message
#> 1 employment employment:lois-lane:daily-planet organization_id Reference target `org:missing` does not exist.
```

Planning writes nothing, so a rejected batch can be corrected and reviewed
again. `graft_commit()` rechecks the reviewed plan and accepts all three
records in one transaction, or none of them:

```r
records$employment$organization_id <- "org:daily-planet"
plan <- graft_plan(store, records, origin)

plan@changes[, c("class", "record_id", "action")]
#>          class                         record_id action
#> 1 organization                  org:daily-planet insert
#> 2       person                  person:lois-lane insert
#> 3   employment employment:lois-lane:daily-planet insert

graft_commit(store, plan)
```

## Keep the old version when a fact changes

A later review changes Lois's role. The update is another reviewable plan, not
an overwrite:

```r
update_plan <- graft_plan(
  store,
  list(person = data.frame(
    id = "person:lois-lane",
    full_name = "Lois Lane",
    job_title = "Investigative editor"
  )),
  graft_provenance(
    producer = "hr-review",
    idempotency_key = "hr-review-2026-08-10"
  )
)

update_plan@changes[, c("record_id", "action", "changed_fields")]
#>          record_id action changed_fields
#> 1 person:lois-lane update      job_title

graft_commit(store, update_plan)

graft_history(store, "person:lois-lane")[
  , c("revision_number", "producer", "changed_fields")
]
#>   revision_number         producer changed_fields
#> 1               2        hr-review      job_title
#> 2               1 directory-import   full_nam....
```

Current retrieval returns the new title. History retains both accepted
versions and the producer behind each change.

## Give an agent bounded reads

An agent is only as trustworthy as the knowledge it reads. graft gives a model
records that were validated on the way in, attributed to a producer, and pinned
so they cannot move mid-session.

`graft_snapshot()` captures the accepted boundary as a serializable, path-free
value, `graft_at()` binds it to a read-only view, and `graft_tools()` turns that
view into four [ellmer](https://ellmer.tidyverse.org/) tools:

```r
snapshot <- graft_snapshot(store)
view <- graft_at(store, snapshot)

tools <- graft_tools(view)
names(tools)
#> [1] "graft_find"    "graft_get"     "graft_query"   "graft_history"

chat <- ellmer::chat_anthropic()
chat$set_tools(tools)
chat$chat("Who works at the Daily Planet, and has that person's title changed?")

graft_close(store)
```

The tools search, retrieve, run bounded advanced operations, and read revision
history. They accept no SQL, connection, path, or write argument, and every
result reports the limit it applied, whether it was truncated, and the digest of
the contract it came from. Fields the contract marks restricted never reach
them.

Writes stay on the reviewed path. An agent that proposes records becomes a
named producer whose plan is validated and inspected like any other, and a
file-editing agent works through a readable Open Knowledge Format tree whose
edits remain proposals until they are reviewed. [Work with
agents](articles/agents.html) covers all three.

## Choose a contract provider

data-dict is the simpler starting point when the domain is naturally tabular.
Its foreign keys let graft reject missing targets, but they are not graph
traversal edges. Move to [LinkML](articles/linkml-schema.html) when you need
relationships that support graph traversal, inheritance, ontology identifiers,
or polymorphic references.

Both providers compile to the same Graft contract and use the same plan,
commit, retrieval, and history functions. The provider changes how the domain
is described; it does not create another way to write accepted knowledge.

## Continue learning

- [Get started](articles/getting-started.html) works through this example with
  its results, then hands the store to an agent.
- [Use a data-dict contract](articles/data-dict-schema.html) covers table-first
  authoring, compilation, and what the table profile enforces.
- [Review knowledge changes](articles/knowledge-change-control.html) explains
  plans, commit preconditions, and retries.
- [Retrieve current records and history](articles/retrieval.html) maps each read
  function to its job.
- [Work with agents](articles/agents.html) covers bounded tools, pinned
  snapshots, agent-authored proposals, and file-editing agents.
- [Add graph semantics with LinkML](articles/linkml-schema.html) continues from
  governed tables to typed traversal relationships.
- [Understand the architecture](articles/architecture.html) explains storage,
  projections, and selective use of S7.
