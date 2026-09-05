# incomplete, incompatible and inaccessible checkpoints fail as a whole

    Code
      example$read_reuse_basis(store, partial, function(ids) TRUE)
    Condition
      Error:
      ! The checkpoint does not contain its complete declared closure.

---

    Code
      example$read_reuse_basis(store, altered, function(ids) TRUE)
    Condition
      Error:
      ! An exact selected revision is unavailable.

---

    Code
      example$read_reuse_basis(store, basis, function(ids) FALSE)
    Condition
      Error:
      ! Reuse is not authorized.

---

    Code
      example$reuse_ids(paste0("id-", seq_len(1001L)))
    Condition
      Error:
      ! Select at most 1,000 unique, non-empty record IDs.

