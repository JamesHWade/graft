# Preserve immutable artifact content

Create or reopen a local artifact store, save opaque bytes, and resolve
an exact revision. Saving grants no approval, access or execution
authority.

## Usage

``` r
graft_store(
  path,
  create = FALSE,
  max_bytes = 64 * 1024^2,
  max_revision_bytes = 1024^2
)
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

## Value

`graft_store()` returns a
[LocalArtifactStore](https://jameshwade.github.io/graft/reference/LocalArtifactStore.md).

## Details

Identity, media-type and reference strings are normalized to plain UTF-8
character values without R attributes.

Local stores support trusted files with one writer. SHA-256 digests
identify content and metadata. Identical saves return the same
reference; corrections retain earlier revisions. There is no mutable
latest pointer.

Payloads are published before immutable revision metadata, using staged
files in the destination directory. A failed save can leave unreferenced
bytes; retries reuse verified content. Orphans are retained rather than
deleted automatically. Successful reads verify metadata, payload size
and digest. Interrupted writes cannot yield a successful incomplete
reference, but this interface does not promise power-loss durability,
concurrent publication, authorization, erasure or backup recovery.
Applications own access and policy. Local handles contain no open
connections and need no closing. For transaction-scoped database
persistence, use
[`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md)
with the same artifact APIs.

## Examples

``` r
path <- tempfile("artifacts-")
store <- graft_store(path, create = TRUE)
ref <- graft_save(store, "A retained report", "report:daily")
reopened <- graft_store(path)
graft_read(reopened, ref)@data
#> [1] "A retained report"
unlink(path, recursive = TRUE)
```
