# The result of a current reviewed-artifact lookup

`Recall` reports a point-in-time `status` of `missing`, `withdrawn`, or
`accepted`. Missing and withdrawn results contain no materialized
payload. Accepted results contain the current verified decision,
selection, roots, and complete materialized dependency closure.

## Usage

``` r
Recall(
  status = character(0),
  decision = NULL,
  selection = NULL,
  roots = NULL,
  artifacts = NULL
)
```

## Arguments

- status:

  Lookup status.

- decision:

  Current verified decision, or `NULL` when missing.

- selection:

  Current verified selection, or `NULL` when missing or withdrawn.

- roots:

  Materialized root artifacts for an accepted recall.

- artifacts:

  Complete materialized closure for an accepted recall.
