# Use a LinkML schema with graft

This article starts with an ordinary LinkML schema. It does not import
graft’s core schema or use graft annotations.

The example is based on LinkML’s [PersonInfo
tutorial](https://linkml.io/linkml/intro/tutorial01.html), which
introduces classes and attributes with a small `Person` model. This
version adds an `Organization` class and the tutorial’s suggested
employment relationship.

## Write the schema

``` r

library(graft)

schema_file <- system.file(
  "extdata",
  "personinfo.linkml.yaml",
  package = "graft"
)
```

The complete schema is:

``` yaml
id: https://w3id.org/graft/examples/personinfo
name: personinfo
title: Person information
description: A small people and organizations schema based on LinkML PersonInfo.
version: 0.1.0
prefixes:
  linkml: https://w3id.org/linkml/
  personinfo: https://w3id.org/graft/examples/personinfo/
  sdo: https://schema.org/
imports:
  - linkml:types
default_prefix: personinfo
default_range: string

classes:
  Person:
    class_uri: sdo:Person
    attributes:
      id:
        identifier: true
        required: true
        slot_uri: sdo:identifier
      full_name:
        required: true
        slot_uri: sdo:name
      aliases:
        multivalued: true
        slot_uri: sdo:alternateName
      age:
        range: integer
        minimum_value: 0
      employed_by:
        range: Organization
        multivalued: true
        inlined: false
        slot_uri: sdo:worksFor

  Organization:
    class_uri: sdo:Organization
    attributes:
      id:
        identifier: true
        required: true
        slot_uri: sdo:identifier
      name:
        required: true
        slot_uri: sdo:name
```

These are standard LinkML features:

- `classes` define `Person` and `Organization` records;
- `attributes` define their fields;
- `identifier: true` marks each class identifier;
- `required`, `range`, and `minimum_value` add constraints;
- `multivalued: true` represents repeated values; and
- `slot_uri` and `class_uri` connect local names to Schema.org terms.

There is no graft-specific authoring requirement in this file.

## Compile the schema

Compile the LinkML file into a graft manifest:

``` r

kg_compile_schema(
  schema_file,
  "personinfo.graft.json"
)
```

Compilation is the only step that uses Python and `linkml-runtime`.
Commit the generated `.graft.json` file with the source schema.
Applications can then load the manifest without Python.

The package includes a compiled copy so the rest of this article is
executable:

``` r

manifest_file <- system.file(
  "extdata",
  "personinfo.graft.json",
  package = "graft"
)
schema <- kg_schema(manifest_file)

kg_classes(schema)
#>          class role statement_shape        table id_policy
#> 1 Organization node            <NA> organization   require
#> 2       Person node            <NA>       person   require
kg_slots(schema, "Person")
#>    class        slot        range relational_type required multivalued
#> 1 Person         age      integer          BIGINT    FALSE       FALSE
#> 2 Person     aliases       string         VARCHAR    FALSE        TRUE
#> 3 Person  created_at     datetime       TIMESTAMP    FALSE       FALSE
#> 4 Person employed_by Organization         VARCHAR    FALSE        TRUE
#> 5 Person   full_name       string         VARCHAR     TRUE       FALSE
#> 6 Person          id       string         VARCHAR     TRUE       FALSE
#> 7 Person  updated_at     datetime       TIMESTAMP    FALSE       FALSE
#>   identifier object_reference enum     column
#> 1      FALSE            FALSE <NA>        age
#> 2      FALSE            FALSE <NA>       <NA>
#> 3      FALSE            FALSE <NA> created_at
#> 4      FALSE             TRUE <NA>       <NA>
#> 5      FALSE            FALSE <NA>  full_name
#> 6       TRUE            FALSE <NA>         id
#> 7      FALSE            FALSE <NA> updated_at
```

For a plain LinkML class, graft supplies conservative storage defaults:

- a concrete class becomes a node table;
- a scalar string-like `id` remains the record identifier;
- scalar attributes become columns;
- multivalued attributes become related tables;
- class-valued attributes become references;
- common text fields provide a display label and basic search fields;
  and
- `created_at` and `updated_at` are added to the runtime manifest.

These defaults affect the compiled manifest, not the source LinkML file.

## Create the DuckDB store

``` r

store <- suppressMessages(kg_connect_duckdb(schema, ":memory:"))
kg_init(store)
```

Use a file path instead of `":memory:"` when the store should persist
across R sessions.

## Write LinkML-shaped records

The input data use the class and attribute names from the LinkML schema.
An object reference contains the identifier of the referenced record. A
multivalued attribute uses a list-column.

``` r

records <- list(
  Organization = data.frame(
    id = "org:daily-planet",
    name = "Daily Planet"
  ),
  Person = data.frame(
    id = "person:clark-kent",
    full_name = "Clark Kent",
    aliases = I(list(c("Superman", "Kal-El"))),
    age = 35L,
    employed_by = I(list("org:daily-planet"))
  )
)

kg_ingest(
  store,
  kg_batch(
    producer = "linkml-example",
    idempotency_key = "personinfo-v1"
  ),
  records
)
#> <kg_ingest_result> committed graft:01KXX950SGKQNY051JD0REH470
#>   inserted: 2
#>   updated:  0
#>   matched:  0
#>   observed: 2
```

The two classes are committed in one transaction. The reference from
`Person.employed_by` is checked against both records already in the
store and records staged in the same batch.

## Query the records

[`kg_records()`](https://jameshwade.github.io/graft/reference/kg_records.md)
returns a lazy dbplyr table:

``` r

people <- kg_records(store, "Person")

people |>
  dplyr::select(id, full_name, age) |>
  dplyr::collect()
#> # A tibble: 1 × 3
#>   id                full_name    age
#>   <chr>             <chr>      <dbl>
#> 1 person:clark-kent Clark Kent    35
```

The inferred text fields are available to
[`kg_find()`](https://jameshwade.github.io/graft/reference/kg_find.md):

``` r

kg_find(store, "Clark", class = "Person", limit = 5)
#>                  id  class      label score
#> 1 person:clark-kent Person Clark Kent     6
```

[`kg_get()`](https://jameshwade.github.io/graft/reference/kg_get.md)
hydrates the record and its multivalued fields:

``` r

person <- kg_get(store, "person:clark-kent")

person$record[c("id", "full_name", "age")]
#> $id
#> [1] "person:clark-kent"
#> 
#> $full_name
#> [1] "Clark Kent"
#> 
#> $age
#> [1] 35
person$record$aliases
#> [1] "Kal-El"   "Superman"
person$record$employed_by
#> [1] "org:daily-planet"
```

## Add graft semantics only when needed

Ordinary LinkML describes record structure, identifiers, ranges,
cardinality, and semantic mappings. That is enough for baseline storage
and querying.

Some knowledge-store decisions are not part of a general LinkML schema.
For example, a project may want to distinguish narrative claims from
normalized semantic statements, connect claims to exact evidence
locations, normalize external identifiers, or choose weighted search
fields.

For those cases, import `graft-core.linkml` and extend one of graft’s
optional roles:

- `GraftNarrativeStatement`
- `GraftSemanticStatement`
- `GraftSource`
- `GraftEvidence`
- `GraftMention`
- `GraftEdge`
- `GraftMetadata`

The package’s
[`materials.linkml.yaml`](https://github.com/JamesHWade/graft/blob/main/inst/extdata/materials.linkml.yaml)
shows that enriched form. Start with ordinary LinkML and add these roles
only when the application needs their behavior.
