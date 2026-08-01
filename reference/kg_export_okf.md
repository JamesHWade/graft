# Export accepted Graft knowledge as an Open Knowledge Format bundle

`kg_export_okf()` writes a deterministic [Open Knowledge
Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf)
(OKF) v0.2 directory from accepted Graft revisions. The bundle is a
human-readable projection for agents, Git, and documentation tools. The
active LinkML-derived manifest remains the executable contract for
identity, validation, storage, and retrieval.

## Usage

``` r
kg_export_okf(
  store,
  path = NULL,
  classes = NULL,
  as_of = NULL,
  limit = 5000,
  overwrite = FALSE
)
```

## Arguments

- store:

  An initialized `kg_store`.

- path:

  Destination directory. The default uses the store's managed OKF
  directory. It need not already exist.

- classes:

  Optional concrete classes to export. The default exports all public
  classes in the active manifest.

- as_of:

  Optional committed batch identifier or scalar `POSIXt` time. The
  default exports current accepted record heads.

- limit:

  Maximum number of concepts. An export that exceeds the limit fails
  rather than writing a partial bundle.

- overwrite:

  Whether to replace an existing Graft-produced OKF bundle.

## Value

A `kg_okf_bundle` summary.

## Details

Every concept includes a `graft` frontmatter extension with stable
record, revision, batch, and schema identity. Object references become
Markdown links, and direct or claim-evidence source references become
OKF `sources`. Sensitive slots remain excluded through the historical
manifest that governed each exported revision.

Exports are bounded and atomic. Existing directories are never replaced
unless `overwrite = TRUE` and the directory identifies itself as a
Graft-produced OKF bundle. The managed directory is reserved for a
complete projection of current accepted state; selected or historical
exports must use another `path`.

## Examples

``` r
if (FALSE) { # \dontrun{
bundle <- kg_export_okf(store, "knowledge/okf")
bundle
} # }
```
