# An exact immutable artifact reference

`ArtifactRef` identifies one logical artifact identity and one immutable
revision. It is a value descriptor; it does not grant access to the
artifact.

## Usage

``` r
ArtifactRef(id = character(0), revision = character(0))
```

## Arguments

- id:

  Stable artifact identity.

- revision:

  Lowercase SHA-256 digest of the immutable revision metadata.
