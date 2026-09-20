# A result from a current reviewed-artifact lookup

`Recall` reports a point-in-time `status` of `missing`, `withdrawn`, or
`accepted`. Missing and withdrawn results contain no artifact content.
Accepted results contain the current verified decision, selection, root
artifacts, and every artifact in the verified dependency closure.

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

  Root artifacts with their retained bytes and metadata for an accepted
  recall.

- artifacts:

  All artifacts in the accepted dependency closure, with their retained
  bytes and metadata.
