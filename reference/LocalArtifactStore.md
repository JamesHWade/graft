# Local artifact store

Local artifact store

## Usage

``` r
LocalArtifactStore(
  max_bytes = integer(0),
  max_revision_bytes = integer(0),
  lock_timeout = 10,
  path = character(0)
)
```

## Arguments

- max_bytes:

  Maximum payload bytes for one artifact and the complete dependency set
  it references.

- max_revision_bytes:

  Maximum encoded revision metadata bytes.

- lock_timeout:

  Seconds to wait for another process's decision in the same stream, or
  for the store's lock, before giving up.

- path:

  Normalized local store directory.
