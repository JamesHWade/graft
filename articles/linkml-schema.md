# Use a LinkML contract with graft

LinkML is graft’s richer ontology- and graph-oriented contract provider.
It defines the classes and fields that a workflow may submit, which
values are required, how records are identified, and which fields refer
to other records. graft compiles it into the same canonical runtime
contract used by every provider. That compiled contract governs
planning, accepted revisions, retrieval, history, and readable
projections; LinkML itself is never the revision ledger.

Choose LinkML when you need inheritance, class and slot ontology URIs,
permissible-value meanings, polymorphic references, graph traversal
relationships, or Graft-specific record and statement semantics. For a
strict table-first alternative with richer dictionary metadata, see [Use
a data-dict contract with
graft](https://jameshwade.github.io/graft/articles/data-dict-schema.md).

An ordinary LinkML schema is enough. It does not need to import a graft
base schema or define a parallel set of R classes.

The v0.1 compiler intentionally supports a strict LinkML profile. Direct
`is_a` inheritance and class-local `slot_usage` overrides are supported,
but class mixins are rejected at compilation because a flattened mixin
ancestry cannot be independently validated as a single parent chain in
the canonical manifest. Replace a mixin with explicit inheritance or
concrete slots before compiling it for graft.

The compiler also rejects LinkML validation, defaulting, composition,
and serialization fields that the canonical manifest does not preserve.
This includes class rules and unique keys; slot equality, cardinality,
expression, default, unit, member, identifier-prefix, and
structured-pattern fields; schema bindings and slot-name constraints;
and enum identity or enum and permissible-value inheritance. Custom
LinkML types are also rejected because their inherited constraints do
not have a lossless `graft-table-v1` representation. Supported primitive
ranges are `boolean`, `date`, `datetime`, `decimal`, `double`, `float`,
`integer`, `string`, `time`, `uri`, and `uriorcurie`; other LinkML
built-ins are rejected until Graft can execute their lexical semantics.
URI and URI-or-CURIE values must be complete RFC 3986 ASCII URIs, or
prefixed CURIEs for `uriorcurie`, with valid percent escapes. Relative
references are rejected. Supported requiredness, scalar or list shape,
enum membership, pattern, and numeric bounds remain executable Graft
validation rules. The strict boundary prevents a source constraint from
looking active after it has been dropped.

## Write the domain contract

This small schema is based on the LinkML PersonInfo tutorial:

``` yaml
id: https://w3id.org/graft/examples/personinfo
name: personinfo
version: 0.1.0
prefixes:
  linkml: https://w3id.org/linkml/
  sdo: https://schema.org/
imports:
  - linkml:types

classes:
  Person:
    class_uri: sdo:Person
    attributes:
      id:
        identifier: true
        required: true
      full_name:
        required: true
      aliases:
        multivalued: true
      age:
        range: integer
        minimum_value: 0
      employed_by:
        range: Organization
        multivalued: true
        inlined: false

  Organization:
    class_uri: sdo:Organization
    attributes:
      id:
        identifier: true
        required: true
      name:
        required: true
```

This contract says that both classes require explicit identifiers, that
names are required, that age cannot be negative, and that `employed_by`
values must refer to organizations.

## Compile or load once

[`graft_schema()`](https://jameshwade.github.io/graft/reference/graft_schema.md)
accepts LinkML YAML, data-dict YAML or trusted resolved `export-spec`
JSON, and a compiled `.graft.json` contract. This article follows the
LinkML path.

``` r

library(graft)

schema <- graft_schema(
  "personinfo.linkml.yaml",
  output = "personinfo.graft.json"
)
```

Compiling YAML resolves the LinkML import closure and creates a
canonical manifest with stable source, structure, and build digests.
Compilation requires Python and `linkml-runtime`. Commit the YAML and
compiled manifest together when reproducible use without Python matters.

Loading the compiled contract is an R-only operation:

``` r

schema <- graft_schema("personinfo.graft.json")
```

The package includes the compiled example used in this article:

``` r

schema <- graft_schema(system.file(
  "extdata",
  "personinfo.graft.json",
  package = "graft"
))
```

## Inspect semantic properties

[`graft_schema()`](https://jameshwade.github.io/graft/reference/graft_schema.md)
returns an immutable S7 `GraftSchema`. Its properties expose stable
semantic information without requiring separate inspection functions.

``` r

schema@name
schema@version
schema@structural_digest
names(schema@classes)

person <- schema@classes$Person
person@label_slot
person@search_slots
names(person@slots)

person@slots$id@identifier
person@slots$full_name@required
person@slots$aliases@multivalued
person@slots$employed_by@object_reference
person@slots$employed_by@range
```

`ClassContract` and `SlotContract` are invariant-rich internal views of
the compiled LinkML contract. They make schema inspection predictable
while domain records remain ordinary data frames.

The complete canonical Graft manifest is available as `schema@manifest`
for tooling that needs lower-level contract details. It is not
necessarily a copy of the source-provider document: for example,
data-dict manifests intentionally redact representative values, dataset
and table origins, and table source locators. Other retained provider
metadata remains public and can contain values embedded manually. Prefer
the typed properties when they cover the question.

## Validate a connected candidate set

Open a store with the schema, then submit records by concrete class:

``` r

store <- graft_open(schema, ":memory:", okf = "disabled")

records <- list(
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
)

plan <- graft_plan(
  store,
  records,
  graft_provenance(
    producer = "linkml-example",
    idempotency_key = "personinfo-v1"
  )
)

plan@valid
plan@changes
plan@issues
```

Planning validates the complete candidate set before anything is
accepted. The organization and person can therefore arrive together: the
relationship is checked against both accepted records and candidates in
the same plan.

List-columns represent multivalued LinkML fields. Scalar fields use
ordinary atomic columns. The data-frame boundary stays familiar even
though the schema, provenance, plan, and store use S7 to protect their
invariants.

``` r

if (plan@valid) {
  graft_commit(store, plan)
}
```

## Let the contract govern retrieval

The compiled contract identifies public search fields, labels,
relationships, and sensitive fields. Retrieval applies those rules to
the active accepted revisions.

``` r

graft_find(store, "Clark", class = "Person", limit = 5)

person <- graft_get(store, "person:clark-kent")
person$record

graft_query(
  store,
  operation = "neighbors",
  request = list(
    id = "person:clark-kent",
    projection = "semantic",
    max_nodes = 25,
    max_edges = 50
  )
)
```

[`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md)
exposes fixed, bounded operations rather than storage-specific queries.
A relationship projection is rebuildable from accepted revisions and the
contract; it is not a second place to write knowledge.

This graph behavior is a reason to choose LinkML. Under the strict
data-dict profile, scalar foreign keys are checked as references but do
not become graph traversal edges.

## Change the contract deliberately

Schema digests are part of every plan and accepted revision. Editing the
LinkML source therefore creates a new contract version rather than
silently changing the meaning of existing knowledge.

Under v0.1, graft can register a compatible semantic contract and
rebuild its derived views. A change that requires transforming accepted
payloads calls for rebuilding the development store from source records.
Historical revisions always retain the exact contract digest that
governed their acceptance.

``` r

graft_close(store)
```
