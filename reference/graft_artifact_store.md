# Preserve immutable artifact content

Create or reopen a local artifact store, save opaque bytes, and resolve
an exact revision. Saving grants no approval, access or execution
authority.

## Usage

``` r
graft_artifact_store(
  path,
  create = FALSE,
  max_bytes = 64 * 1024^2,
  max_revision_bytes = 1024^2
)

graft_artifact_save(
  store,
  id,
  bytes,
  media_type,
  dependencies = list(),
  max_artifacts = 1000L
)

graft_artifact_read(store, ref)
```

## Arguments

- path:

  Directory for a Graft artifact store, distinct from a native graph
  store. Creation requires a missing or empty directory. Filesystem
  paths follow platform limits, independently of artifact identity byte
  limits.

- create:

  Create a new store? Defaults to `FALSE` for safe reopening.

- max_bytes:

  Maximum payload bytes per artifact to save or read in this handle.
  Dependency traversal also applies this limit to aggregate payloads.

- max_revision_bytes:

  Maximum encoded metadata bytes per revision to save or read through
  this handle, a positive whole number. Defaults to 1 MiB (`1024^2`),
  independently of payload and dependency-count bounds. Increase it for
  large dependency lists, including when reopening the store.

- store:

  A handle returned by `graft_artifact_store()`.

- id:

  Stable, nonempty artifact identity chosen by the caller, at most 1024
  UTF-8 bytes, without padding or control characters.

- bytes:

  Raw vector containing the complete payload. Attributes are discarded;
  only the byte contents are retained. Content is never deserialized or
  executed by these functions.

- media_type:

  Nonempty media type describing the opaque payload, at most 1024 UTF-8
  bytes, without padding or control characters.

- dependencies:

  List of exact dependency references. The complete closure is verified
  before saving. No relationships are inferred from payloads.

- max_artifacts:

  Maximum distinct dependency references traversed before saving. Their
  total payload size is also limited by `max_bytes`.

- ref:

  Exact reference: a list with `id` and `revision` strings, as returned
  by `graft_artifact_save()`.

## Value

`graft_artifact_store()` returns a local store handle.
`graft_artifact_save()` returns a list containing `id` and `revision`.
`graft_artifact_read()` returns `ref`, `metadata` and verified raw
`bytes`.

## Details

Identity, media-type and reference strings are normalized to plain UTF-8
character values without R attributes.

This interface supports trusted local files with one writer. SHA-256
digests identify content and metadata. Identical saves return the same
reference; corrections retain earlier revisions. There is no mutable
latest pointer.

Payloads are published before immutable revision metadata, using staged
files in the destination directory. A failed save can leave unreferenced
bytes; retries reuse verified content. Orphans are retained rather than
deleted automatically. Successful reads verify metadata, payload size
and digest. Interrupted writes cannot yield a successful incomplete
reference, but this interface does not promise power-loss durability,
concurrent publication, authorization, erasure or backup recovery.
Applications own access and policy. Handles contain no open connections
and need no closing.

## Examples

``` r
path <- tempfile("artifacts-")
store <- graft_artifact_store(path, create = TRUE)
ref <- graft_artifact_save(
  store, "report:daily", charToRaw("A retained report"), "text/plain"
)
reopened <- graft_artifact_store(path)
rawToChar(graft_artifact_read(reopened, ref)$bytes)
#> [1] "A retained report"
unlink(path, recursive = TRUE)
```
