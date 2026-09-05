# restricted metadata and provider values stay out of every discovery consumer

    Code
      graft_dictionary(view, "person", "job_title")
    Condition
      Error in `graft_dictionary()`:
      ! Select an available public dictionary table and column.

# discovery validates selection and paging at the public boundary

    Code
      graft_dictionary(store, field = "id")
    Condition
      Error in `graft_dictionary()`:
      ! Select an available public dictionary table and column.

---

    Code
      graft_dictionary(store, table = "missing")
    Condition
      Error in `graft_dictionary()`:
      ! Select an available public dictionary table and column.

---

    Code
      graft_dictionary(store, limit = 101)
    Condition
      Error in `graft_dictionary()`:
      ! `limit` must be a whole number between 1 and 100, not the number 101.

---

    Code
      graft_dictionary(store, offset = -1)
    Condition
      Error in `graft_dictionary()`:
      ! `offset` must be a whole number between 0 and 1e+06, not the number -1.

---

    Code
      graft_dictionary(fixture$store)
    Condition
      Error in `graft_dictionary()`:
      ! Dictionary discovery requires a data-dict contract.

