# Commons selection rejects system and unknown classes

    Code
      graft_commons_data_source(store, classes = "GraftDefinition")
    Condition
      Error in `commons_selected_classes()`:
      ! Unknown or non-public Commons class selection: GraftDefinition.

---

    Code
      graft_commons_data_source(store, classes = "Missing")
    Condition
      Error in `commons_selected_classes()`:
      ! Unknown or non-public Commons class selection: Missing.
