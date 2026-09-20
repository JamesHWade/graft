# Verify a closed artifact-store backup

Validate a complete backup bundle against a receipt retained outside the
bundle. Verification checks canonical descriptor bytes, exact object
bytes, complete artifact histories, and all caller-supplied bounds.

## Usage

``` r
graft_verify_backup(
  path,
  expected,
  max_objects = 10000L,
  max_total_bytes = 64 * 1024^2,
  max_metadata_bytes = 1024^2,
  max_bundle_metadata_bytes = 4 * 1024^2,
  max_bytes = 64 * 1024^2,
  max_revision_bytes = 1024^2
)
```

## Arguments

- path:

  A local backup bundle path without `..` components.

- expected:

  The independently retained receipt expected for this bundle.

- max_objects:

  Maximum number of stored artifact objects to inspect.

- max_total_bytes:

  Maximum total bytes across stored artifact objects.

- max_metadata_bytes:

  Maximum bytes for one selection or decision object and the aggregate
  bytes of one decision stream.

- max_bundle_metadata_bytes:

  Maximum bytes for the `bundle.json` descriptor.

- max_bytes:

  Maximum payload bytes allowed for content objects.

- max_revision_bytes:

  Maximum bytes allowed for one revision object.

## Value

The canonical verified receipt.

## Details

The receipt is required from an independent application registry; it is
not read from the bundle. Matching scope and generation values identify
the expected image but do not authenticate it or establish current
restore eligibility. Verification never changes the bundle.
