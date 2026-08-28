# graft_calculate() rejects invalid requests with classed errors

    Code
      graft_calculate(store, metrics = "nope")
    Condition
      Error in `definition_resolve_one()`:
      ! No accepted definition resolves `nope`.

---

    Code
      graft_calculate(store, metrics = "entity_count", dimensions = "nope")
    Condition
      Error in `definition_resolve_one()`:
      ! No accepted definition resolves `nope`.

---

    Code
      graft_calculate(store, metrics = "entity_count", where = list(list(column = "label",
        op = "=", value = 1)))
    Condition
      Error in `definition_where_predicates()`:
      ! Every `where` predicate needs string `column`, `op`, and `value` fields.

