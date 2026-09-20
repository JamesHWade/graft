# A verified artifact dependency selection

An `ArtifactSelection` records one exact selection digest, its roots,
and the complete verified dependency closure: the roots and all of their
dependencies. It does not grant approval or access to the selected
artifacts.

## Usage

``` r
ArtifactSelection(id = character(0), roots = NULL, artifacts = NULL)
```

## Arguments

- id:

  Exact selection digest.

- roots:

  Exact root references in caller order.

- artifacts:

  Complete breadth-first dependency closure, including the roots and
  their dependencies.
