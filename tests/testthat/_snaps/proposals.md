# recorded producer output is corrected reviewed and committed idempotently

    Code
      graft_commit(store, graft_proposal_plan(store, raw, provenance))
    Condition
      Error in `validate_commit_plan_replay()`:
      ! The producer/idempotency key is already committed for a different plan.

# malformed proposals fail without losing rows or fields

    Code
      graft_proposal_plan(store, list(person = data.frame(id = "x")), provenance)
    Condition
      Error in `proposal_error()`:
      ! Expected a bounded JSON array of record objects.

---

    Code
      graft_proposal_plan(store, bad, provenance)
    Condition
      Error in `proposal_error()`:
      ! Proposal contains an unknown or restricted column.

---

    Code
      graft_proposal_plan(store, bad, provenance)
    Condition
      Error in `proposal_error()`:
      ! Expected non-null scalar values of the declared JSON type.

---

    Code
      graft_proposal_plan(store, bad, provenance, max_rows = 1)
    Condition
      Error in `proposal_error()`:
      ! Expected a bounded JSON array of record objects.

---

    Code
      graft_proposal_plan(store, bad, provenance)
    Condition
      Error in `proposal_error()`:
      ! Expected a non-empty JSON object with unique names.

# public selection cannot omit required fields or include restricted fields

    Code
      graft_proposal_type(store, "person", fields = list(person = "id"))
    Condition
      Error in `proposal_error()`:
      ! Include every required column and select only public columns.

---

    Code
      graft_proposal_type(store, "person", fields = list(person = c("id", "full_name",
        "age")))
    Condition
      Error in `proposal_error()`:
      ! Include every required column and select only public columns.

---

    Code
      graft_proposal_plan(store, list(person = list(list(id = "person:lois",
        full_name = "Lois", age = 4))), graft_provenance("test", idempotency_key = "restricted"))
    Condition
      Error in `proposal_error()`:
      ! Proposal contains an unknown or restricted column.

---

    Code
      graft_proposal_type(required, "person")
    Condition
      Error in `proposal_error()`:
      ! Include every required column and select only public columns.

---

    Code
      graft_proposal_type(fixture$store)
    Condition
      Error in `proposal_error()`:
      ! Structured proposals require a data-dict contract.

# proposal planning requires provenance replay keys and preserves list element types

    Code
      graft_proposal_plan(store, rows, provenance)
    Condition
      Error in `proposal_error()`:
      ! Expected non-null scalar values of the declared JSON type.

---

    Code
      graft_proposal_plan(store, rows, provenance)
    Condition
      Error in `proposal_error()`:
      ! Expected non-null scalar values of the declared JSON type.

---

    Code
      graft_proposal_plan(store, rows, graft_provenance("test"))
    Condition
      Error in `proposal_error()`:
      ! Structured proposals require an explicit idempotency key.

