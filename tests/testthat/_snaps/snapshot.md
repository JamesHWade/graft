# graft_at rejects snapshots from another store

    Code
      cat(conditionMessage(condition), "\n", sep = "")
    Output
      The snapshot belongs to a different Graft store.

# graft_at rejects a valid future boundary from the same store

    Code
      cat(conditionMessage(condition), "\n", sep = "")
    Output
      The snapshot boundary is newer than the current store.

# graft_at requires its historical schema metadata

    Code
      cat(conditionMessage(condition), "\n", sep = "")
    Output
      The snapshot requires unavailable or invalid historical schema metadata.
      Caused by error in `historical_schema_version()`:
      ! A revision does not have exactly one registered historical manifest.

