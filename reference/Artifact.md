# Materialized immutable artifact content

An `Artifact` contains exact bytes together with the media type and
exact dependency references recorded with those bytes. `data` is decoded
text for `text/*` media types and raw bytes for all other media types.

## Usage

``` r
Artifact(
  ref = ArtifactRef(),
  bytes = raw(0),
  media_type = character(0),
  dependencies = NULL,
  data = NULL
)
```

## Arguments

- ref:

  Exact artifact reference.

- bytes:

  Exact retained bytes.

- media_type:

  Media type recorded for the artifact.

- dependencies:

  Exact dependency references.

- data:

  Decoded scalar text or raw bytes.
