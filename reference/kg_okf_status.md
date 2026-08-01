# Inspect the managed Open Knowledge Format working tree

Reports whether the configured bundle is absent, current, stale relative
to accepted Graft state, locally modified, or incompatible with the
active schema. Status inspection never changes accepted knowledge or the
managed directory.

## Usage

``` r
kg_okf_status(store, path = NULL, deep = TRUE)
```

## Arguments

- store:

  An initialized `kg_store`.

- path:

  Optional bundle directory. The default uses the managed path.

- deep:

  Whether to verify the bundle's content digest.

## Value

A `kg_okf_status` object.
