# Retrieve one current accepted record

`graft_get()` hydrates one current record from its authoritative headed
revision. Sensitive fields are filtered by the active contract. Related
identifiers, claims, and evidence are optional and independently
bounded. A `GraftView` resolves the record and related data at its
pinned boundary.

## Usage

``` r
graft_get(
  store,
  id,
  include = c("identifiers", "claims", "evidence"),
  limits = list(identifiers = 100L, claims = 50L, evidence = 100L)
)
```

## Arguments

- store:

  An initialized `GraftStore` or immutable `GraftView`.

- id:

  One internal record identifier.

- include:

  Related results to include. Supported values are `"identifiers"`,
  `"claims"`, and `"evidence"`.

- limits:

  Named limits for included results.

## Value

An ordinary list containing the public record, related results, limits,
and truncation state.
