# Describe the active knowledge contract

The schema-specific context is generated from the active compiled
manifest. Sensitive slots are omitted. The rendered text is bounded by
an approximate token budget and the structured fields retain the same
safe contract.

## Usage

``` r
kg_context(store, class = NULL, token_budget = 1500)
```

## Arguments

- store:

  An initialized `kg_store`.

- class:

  Optional concrete class restriction.

- token_budget:

  Maximum approximate tokens in the rendered context text.

## Value

A `kg_context` object with bounded text and structured safe details.
