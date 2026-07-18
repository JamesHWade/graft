# Hydrate exactly one record

Hydrate exactly one record

## Usage

``` r
kg_get(
  store,
  id,
  include = c("identifiers", "claims", "evidence"),
  limits = list(identifiers = 100L, claims = 50L, evidence = 100L)
)
```

## Arguments

- store:

  An initialized `kg_store`.

- id:

  One internal record identifier.

- include:

  Related data to include. Supported values are `"identifiers"`,
  `"claims"`, and `"evidence"`.

- limits:

  Named limits for identifiers, claims, and evidence.

## Value

A `kg_record` containing the record and requested related data.
