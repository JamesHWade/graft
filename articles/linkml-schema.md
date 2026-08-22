# Add graph semantics with LinkML

Start with data-dict when the domain is naturally a set of tables. It
gives Graft table and column descriptions, primary keys, supported value
rules, and scalar foreign keys that can be checked before records are
accepted.

LinkML is the next step when the contract must express meaning beyond
those tables. It can define ontology identifiers, inheritance,
polymorphic ranges, and Graft semantic-statement roles. Both providers
compile to the same `.graft.json` runtime contract and use the same
plan, commit, history, and retrieval functions.

There is an important distinction: a checked reference is not
automatically a graph edge. Graft validates ordinary LinkML
object-reference slots, just as it validates supported data-dict foreign
keys. The semantic graph projection is driven by classes declared as
graph-producing edges or semantic statements.

| Need | Start with |
|----|----|
| Tables, columns, keys, enums, and checked scalar foreign keys | data-dict |
| Class and slot ontology identifiers | LinkML |
| Reusable inheritance or polymorphic references | LinkML |
| Subject-predicate-object statements in the semantic graph | LinkML with Graft semantic roles |

## Add ontology identifiers and inheritance

An ordinary LinkML schema can introduce shared fields through
inheritance and attach stable ontology identifiers to classes and slots:

``` yaml
id: https://w3id.org/example/team-directory
name: team_directory
version: 0.1.0
prefixes:
  linkml: https://w3id.org/linkml/
  sdo: https://schema.org/
  team: https://w3id.org/example/team-directory/
default_prefix: team
default_range: string
imports:
  - linkml:types

classes:
  NamedThing:
    abstract: true
    attributes:
      id:
        identifier: true
        required: true
      name:
        required: true

  Person:
    is_a: NamedThing
    class_uri: sdo:Person
    attributes:
      works_for:
        range: Organization
        inlined: false

  Organization:
    is_a: NamedThing
    class_uri: sdo:Organization
```

This contract reuses identity and name fields and validates `works_for`
as an organization reference. That reference alone does not create a
traversal edge. Use a graph-producing statement when the relationship
must participate in the semantic graph.

## Declare a semantic statement

Graft ships a small LinkML core for schemas that need record and
statement roles. To run a complete graph example without introducing
another team-directory fixture, the rest of this guide switches
deliberately to the bundled materials domain. It defines nodes and a
semantic statement:

``` yaml
classes:
  Material:
    is_a: GraftNode
    slots:
      - preferred_name
      - description
      - cas_number

  Measurement:
    is_a: GraftSemanticStatement
    slots:
      - measurement_method
      - temperature
```

`GraftSemanticStatement` supplies `subject`, `predicate`,
`object_entity`, and `object_value`. A concrete statement must have
exactly one object representation. Accepted entity-valued statements
produce the semantic edges used by bounded neighbor retrieval. Narrative
statements remain searchable claims but are excluded from that semantic
edge projection.

This richer behavior is why LinkML follows, rather than replaces, the
simpler data-dict path. Use it when the domain actually needs semantic
graph meaning.

## Compile once, then run in R

[`graft_schema()`](https://jameshwade.github.io/graft/reference/graft_schema.md)
compiles LinkML YAML and its import closure into a canonical
`.graft.json` manifest:

``` r

library(graft)

schema <- graft_schema(
  system.file(
    "extdata",
    "materials.linkml.yaml",
    package = "graft",
    mustWork = TRUE
  ),
  output = "materials.graft.json"
)
```

Compilation requires Python and `linkml-runtime`. Graft rejects source
semantics that its runtime contract cannot preserve instead of silently
downgrading them. [Contract compiler
boundaries](https://jameshwade.github.io/graft/articles/contract-compilers.md)
lists the supported LinkML profile and the exact compilation
dependencies.

Loading a compiled manifest and operating a store are R-only:

``` r

schema <- graft_schema(system.file(
  "extdata",
  "materials.graft.json",
  package = "graft",
  mustWork = TRUE
))
```

Commit the LinkML source and compiled manifest together when users or
deployed workflows should run without Python.

## Inspect what the contract enables

The typed schema properties expose the parts most applications need:

``` r

schema@name
#> [1] "materials"
schema@version
#> [1] "0.1.0"
schema@structural_digest
#> [1] "sha256:2044c075dd8d683af90969868d6454a954266b8a80a06d34cb762e2ab57090e9"
names(schema@classes)
#> [1] "Claim"        "Evidence"     "Material"     "Measurement"  "Source"      
#> [6] "GraftMeasure"

material <- schema@classes$Material
material@role
#> [1] "node"
material@label_slot
#> [1] "preferred_name"
material@search_slots
#> [1] "description"    "preferred_name"

measurement <- schema@classes$Measurement
measurement@role
#> [1] "statement"
measurement@statement_shape
#> [1] "semantic"
measurement@slots$subject@object_reference
#> [1] TRUE
measurement@slots$object_entity@object_reference
#> [1] TRUE
```

The complete manifest is available as `schema@manifest` for lower-level
tooling. Domain records remain ordinary data frames; the S7 schema
object protects the compiled contract and its digests.

## Accept and traverse semantic statements

The materials contract can accept two nodes and a semantic statement in
one plan:

``` r

store <- graft_open(schema, ":memory:", okf = "disabled")

polyethylene_id <- "graft:40X0M02WR9Z55QWFDJYTNS3KX8"
water_id <- "graft:64W8ZFH68S76XQ2MWW0H46Q9Y6"

records <- list(
  Material = data.frame(
    id = c(polyethylene_id, water_id),
    preferred_name = c("Polyethylene", "Water"),
    cas_number = c("9002-88-4", "7732-18-5")
  ),
  Measurement = data.frame(
    id = "graft:0D6WMEBSAMAS7JRQWGT5W44ASR",
    subject = polyethylene_id,
    predicate = "materials:testedWith",
    object_entity = water_id,
    measurement_method = "immersion",
    temperature = 23
  )
)

plan <- graft_plan(
  store,
  records,
  graft_provenance(
    producer = "materials-example",
    idempotency_key = "materials-v1"
  )
)

plan@valid
#> [1] TRUE
plan@changes[, c("class", "record_id", "action"), drop = FALSE]
#>         class                        record_id action
#> 1    Material graft:40X0M02WR9Z55QWFDJYTNS3KX8 insert
#> 2    Material graft:64W8ZFH68S76XQ2MWW0H46Q9Y6 insert
#> 3 Measurement graft:0D6WMEBSAMAS7JRQWGT5W44ASR insert
plan@issues
#> [1] class           input_row       record_id       field          
#> [5] rule            message         condition_class
#> <0 rows> (or 0-length row.names)

stopifnot(plan@valid)
result <- graft_commit(store, plan)
result$inserted
#>    Material Measurement 
#>           2           1
```

Because `Measurement` is a semantic statement, the bounded neighbor
operation can return its subject, object, and predicate:

``` r

neighbors <- graft_query(
  store,
  operation = "neighbors",
  request = list(
    id = polyethylene_id,
    projection = "semantic",
    hops = 1,
    max_nodes = 25,
    max_edges = 50
  )
)

neighbors$nodes[, c("id", "label"), drop = FALSE]
#>                                 id        label
#> 1 graft:40X0M02WR9Z55QWFDJYTNS3KX8 Polyethylene
#> 2 graft:64W8ZFH68S76XQ2MWW0H46Q9Y6        Water
neighbors$edges[, c("subject", "predicate", "object"), drop = FALSE]
#>                            subject            predicate
#> 1 graft:40X0M02WR9Z55QWFDJYTNS3KX8 materials:testedWith
#>                             object
#> 1 graft:64W8ZFH68S76XQ2MWW0H46Q9Y6
```

The graph is a derived read view of accepted revisions. It is not a
separate place to insert or edit relationships.

## Change the contract explicitly

Every plan and accepted revision records the active schema digest.
Editing the LinkML source therefore creates a new contract version
rather than silently changing the meaning of existing knowledge.

During v0.1 development, Graft can register a compatible semantic
contract and rebuild its derived views. A change that transforms
accepted payloads requires rebuilding the development store from source
records. Historical revisions retain the contract digest that governed
their acceptance.

``` r

graft_close(store)
```
