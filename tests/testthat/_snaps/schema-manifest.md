# manifest failures use structured schema conditions

    Code
      kg_slots(kg_schema(tempest_manifest_path()), "MissingClass")
    Condition
      Error in `kg_slots()`:
      ! Unknown concrete class `MissingClass`.
