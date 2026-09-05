# upstream nested representations are distinct from the adapter profile

    Code
      graft_schema(path)
    Condition
      Error in `data_dict_abort()`:
      ! Nested column fields are not supported by the graft-table-v1 profile.

---

    Code
      graft_schema(path)
    Condition
      Error in `data_dict_abort()`:
      ! Nested list columns are not supported by the Graft adapter.

