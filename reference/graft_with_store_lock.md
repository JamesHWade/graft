# Hold a store's lock while an application changes it

Run code while holding the store's lock, so an application can make a
change that spans several Graft calls without another process writing in
between. Every write to a local store holds this lock shared, and
[`graft_manifest()`](https://jameshwade.github.io/graft/reference/graft_manifest.md),
[`graft_plan_replacement()`](https://jameshwade.github.io/graft/reference/graft_plan_replacement.md),
[`graft_replace()`](https://jameshwade.github.io/graft/reference/graft_plan_replacement.md),
[`graft_backup()`](https://jameshwade.github.io/graft/reference/graft_backup.md),
and
[`graft_restore()`](https://jameshwade.github.io/graft/reference/graft_restore.md)
hold it exclusively.

## Usage

``` r
graft_with_store_lock(store, code, exclusive = TRUE)
```

## Arguments

- store:

  A handle returned by
  [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  or
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md).

- code:

  Code to run while the lock is held.

- exclusive:

  `TRUE` to keep every other process out of the store, `FALSE` to share
  the lock with other writers.

## Value

The value of `code`. If the lock is not free within the store's
`lock_timeout`, an error of class `graft_store_busy_error` is signalled
and `code` is not run. A store this process cannot write has no lock it
can take, so holding it is an error too.

## Details

A host that forgets an artifact by building a replacement store holds
the old store's lock exclusively while it plans, copies, and switches to
the replacement, and wraps each of its writes in a shared hold that
first checks the store is still current. A write that was waiting on the
lock then sees the switch and goes to the new store instead of the
retired one.

Graft calls inside `code` run under the lock already held. An exclusive
hold cannot be taken inside a shared one. PostgreSQL stores run `code`
directly: the host's transaction and scope lock already serialize it.

## Examples

``` r
path <- tempfile("artifacts-")
store <- graft_store(path, create = TRUE)
ref <- graft_with_store_lock(store, graft_save(store, "Evidence", "report"))
graft_read(store, ref)@data
#> [1] "Evidence"
unlink(path, recursive = TRUE)
```
