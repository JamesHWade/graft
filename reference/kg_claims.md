# Retrieve narrative and semantic claims about an entity

Narrative statements are discovered through `primary_subject` and
generated `about` relations. Semantic statements are discovered through
`subject` and `object_entity`. Narrative statements are never assigned
fabricated predicates.

## Usage

``` r
kg_claims(
  store,
  entity_id,
  predicate = NULL,
  include_superseded = FALSE,
  limit = 100
)
```

## Arguments

- store:

  An initialized `kg_store`.

- entity_id:

  One internal entity identifier.

- predicate:

  Optional semantic predicate restriction.

- include_superseded:

  Whether non-active statements may be returned.

- limit:

  Maximum statements to return.

## Value

A bounded data frame. `qualifiers`, ordinary `attributes`, and hydrated
`evidence` are separate list-columns.
