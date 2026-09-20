# Publish a validated shared vocabulary release

The source companion and its pinned dictionary files are validated by
the upstream data-dict CLI and retained as one immutable artifact
selection. The returned value is a typed release re-read from the store
after publication.

## Usage

``` r
graft_publish_vocabulary(store, path)
```

## Arguments

- store:

  An
  [ArtifactStore](https://jameshwade.github.io/graft/reference/ArtifactStore.md)
  returned by
  [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  or
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md).

- path:

  Path to a `graft-bindings/1` JSON companion file. Referenced
  vocabulary JSON and dictionary YAML files must be siblings pinned by
  SHA-256.

## Value

A
[VocabularyRelease](https://jameshwade.github.io/graft/reference/VocabularyRelease.md)
containing the verified selection and the complete retained vocabulary,
bindings, dictionaries, references, and context.
