# Disconnect a graft store

Disconnecting is safe to call more than once. Graft closes only
connections it created; caller-supplied connections remain open.

## Usage

``` r
kg_disconnect(store)
```

## Arguments

- store:

  A `kg_store` object.

## Value

`store`, invisibly.
