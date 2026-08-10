# Use a data-dict contract with graft

Use data-dict when the knowledge you have today is tabular. A data
dictionary names the tables and columns, documents their meaning, and
declares constraints and relationships. graft compiles the supported
parts into the contract used to review candidate records.

The source contract does not become the knowledge store. Accepted
records and their revisions live in graft’s DuckDB ledger.

## Author once, then use the resolved dictionary

The package includes a small team directory in two forms:

- `team-directory.data-dict.yaml` is the human-authored source; and
- `team-directory.data-dict.json` is the resolved output from
  `data-dict export-spec`.

Contract authors install the [data-dict
CLI](https://data-dict.tidyverse.org/), validate the readable YAML, and
resolve it once:

``` bash
data-dict validate-spec team-directory.data-dict.yaml
data-dict export-spec team-directory.data-dict.yaml --pretty > team-directory.data-dict.json
```

The rest of this guide starts from the shipped resolved JSON. That keeps
the runnable package lesson R-only; the bundled JSON is the exact export
of the bundled YAML under the CLI revision documented in the [compiler
reference](https://jameshwade.github.io/graft/articles/contract-compilers.md).

``` r

library(graft)

resolved_path <- system.file(
  "extdata",
  "team-directory.data-dict.json",
  package = "graft",
  mustWork = TRUE
)

schema <- graft_schema(resolved_path)

schema@name
#> [1] "team_directory"
schema@version
#> [1] "0.1.0"
names(schema@classes)
#> [1] "organization" "person"       "employment"
```

When compiling this resolved source without `output`,
[`graft_schema()`](https://jameshwade.github.io/graft/reference/graft_schema.md)
writes a temporary `.graft.json` manifest. Supply an output path when
the compiled contract should be committed or deployed as an artifact:

``` r

schema <- graft_schema(
  resolved_path,
  output = "team-directory.graft.json"
)
```

## See how tables become a contract

The source YAML uses familiar table concepts. Its essential structure
is:

``` yaml
$version: 0.1.0
$learn_more: https://data-dict.tidyverse.org/
name: team_directory
version:
  number: 0.1.0

tables:
  - name: organization
    columns:
      - name: id
        type: string
        constraints: [primary_key]
        examples: ["org:daily-planet"]
      - name: name
        type: string
        constraints: [required]
        examples: ["Daily Planet"]

  - name: person
    columns:
      - name: id
        type: string
        constraints: [primary_key]
        examples: ["person:lois-lane"]
      - name: full_name
        type: string
        constraints: [required]
        examples: ["Lois Lane"]
      - name: job_title
        type: string
        examples: ["Reporter"]

  - name: employment
    columns:
      - name: id
        type: string
        constraints: [primary_key]
        examples: ["employment:lois-lane:daily-planet"]
      - name: person_id
        type: string
        constraints: [required, foreign_key]
        examples: ["person:lois-lane"]
      - name: organization_id
        type: string
        constraints: [required, foreign_key]
        examples: ["org:daily-planet"]

relationships:
  - join: employment.person_id = person.id
    cardinality: many-to-one
  - join: employment.organization_id = organization.id
    cardinality: many-to-one
```

The adapter maps each table to a Graft class and each column to a slot.
Primary keys establish record identity. Scalar foreign keys become
reference checks.

``` r

employment <- schema@classes$employment

names(employment@slots)
#> [1] "id"              "person_id"       "organization_id"
employment@slots$person_id@required
#> [1] TRUE
employment@slots$person_id@object_reference
#> [1] TRUE
employment@slots$person_id@range
#> [1] "person"
```

Candidate inputs use the same table names:

``` r

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
    organization_id = "org:daily-planet"
  )
)
```

The [getting-started
guide](https://jameshwade.github.io/graft/articles/getting-started.md)
opens an empty store, shows a missing foreign key being rejected,
commits this corrected candidate set, and retrieves two revisions of the
person record.

## Know what the table profile enforces

The current `graft-table-v1` profile is deliberately narrower than
data-dict itself:

- every table has exactly one primary key named `id`, represented as a
  scalar string;
- IDs are non-empty and globally unique across all tables in one Graft
  store;
- every YAML column declares a type;
- non-key columns are scalars or one-level lists of scalar values;
- foreign keys are scalar strings that target another table’s primary
  `id`; and
- resolved `foreign_key` constraints and `references` metadata must
  agree.

Struct columns, nested lists, list-valued foreign keys, and numeric ID
types are rejected rather than converted. Use quoted strings for
identifiers and codes.

Some data-dict metadata remains descriptive. Graft does not currently
execute non-primary uniqueness, representative ranges, assertion text,
relationship cardinality, join aliases, conflicts, range joins, or
multi-column joins. Scalar foreign keys are validated references, not
graph traversal edges.

The compiled mapping report records these boundaries:

``` r

schema@manifest$dictionary$profile
#> [1] "graft-table-v1"
unlist(schema@manifest$dictionary$mapped[c(
  "tables_to_classes",
  "columns_to_slots",
  "foreign_keys_to_object_references"
)])
#>                 tables_to_classes                  columns_to_slots 
#>                                 3                                 8 
#> foreign_keys_to_object_references 
#>                                 2
```

The [compiler
reference](https://jameshwade.github.io/graft/articles/contract-compilers.md)
is the authoritative list of descriptive or unsupported data-dict
semantics.

## Compile YAML when authoring the contract

The YAML route lets data-dict resolve its own source format. It requires
the optional `data-dict` executable; graft never downloads or installs
it during package use.

``` r

yaml_path <- system.file(
  "extdata",
  "team-directory.data-dict.yaml",
  package = "graft",
  mustWork = TRUE
)

options(graft.data_dict_cli = "/path/to/data-dict")

schema <- graft_schema(
  yaml_path,
  output = "team-directory.graft.json"
)
```

graft runs `data-dict export-spec`; it does not run data-dict’s metadata
or data validation commands. Teams commonly resolve YAML in a
schema-authoring or CI environment and commit the YAML, resolved JSON,
and compiled `.graft.json` together.

Resolved JSON is trusted build input. graft checks its supported export
version and structure, but cannot prove that another program actually
produced it with `export-spec`.

See [Contract compiler
details](https://jameshwade.github.io/graft/articles/contract-compilers.md)
for CLI pinning, compiler provenance, digest behavior, public-manifest
redaction, exact numeric and datetime rules, and the LinkML compiler’s
strict profile.

## Where to go next

Continue with [change
control](https://jameshwade.github.io/graft/articles/knowledge-change-control.md)
to review and accept plans, then [retrieval and
history](https://jameshwade.github.io/graft/articles/retrieval.md) to
read the accepted knowledge and its revisions.

Use LinkML when the contract needs inheritance, class or predicate URIs,
polymorphic references, Graft record roles, narrative or semantic
statements, custom identity policies, qualifier fields, or graph
traversal relationships. The [LinkML
guide](https://jameshwade.github.io/graft/articles/linkml-schema.md)
continues from the same plan and commit model; only the contract
provider changes.
