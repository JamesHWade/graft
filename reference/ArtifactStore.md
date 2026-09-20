# Abstract artifact store

`ArtifactStore` is the common S7 type for bounded local and PostgreSQL
artifact stores. It cannot be instantiated directly.

## Usage

``` r
ArtifactStore(max_bytes = integer(0), max_revision_bytes = integer(0))
```

## Arguments

- max_bytes:

  Maximum payload bytes for one artifact and the complete dependency set
  it references.

- max_revision_bytes:

  Maximum encoded revision metadata bytes.
