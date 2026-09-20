# An exact immutable artifact reference

`ArtifactRef` identifies one logical artifact identity and one immutable
revision. It only identifies the artifact; it does not grant access to
it.

## Usage

``` r
ArtifactRef(id = character(0), revision = character(0))
```

## Arguments

- id:

  Stable artifact identity.

- revision:

  Lowercase SHA-256 digest of the immutable revision metadata.
