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

# Commons public contract changes fail before source construction

    Code
      conditionMessage(condition)
    Output
      [1] "The installed Commons public contract is not supported. Commons must export `data_source()`."

