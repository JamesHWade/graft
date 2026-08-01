# Synchronize the managed Open Knowledge Format working tree

`kg_sync_okf()` atomically replaces a Graft-produced OKF bundle with a
deterministic projection of the store's current accepted state. It never
replaces an unrelated directory. Synchronization is explicit so a
filesystem failure cannot be confused with a failed database
transaction.

## Usage

``` r
kg_sync_okf(store, path = NULL, limit = 5000)
```

## Arguments

- store:

  An initialized `kg_store`.

- path:

  Optional destination. The default uses the managed OKF directory.

- limit:

  Maximum number of concepts. A larger store fails without writing a
  partial bundle.

## Value

A `kg_okf_bundle` summary.
