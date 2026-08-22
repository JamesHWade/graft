# graft_measure() rejects unknown names, arguments, and dimensions

    Code
      graft_measure(store, "nope")
    Condition
      Error in `graft_measure()`:
      ! No accepted measure is named `nope`. Accepted measures: `entity-count`.

---

    Code
      graft_measure(store, "entity-count", arguments = list(nope = 1))
    Condition
      Error in `graft_measure()`:
      ! Unknown measure argument `nope`. Declared parameters: `label`.

---

    Code
      graft_measure(store, "entity-count", by = "nope")
    Condition
      Error in `graft_measure()`:
      ! Unknown measure dimension `nope`. Declared dimensions: `label`, `preferred_name`.

