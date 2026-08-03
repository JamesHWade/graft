# graft provenance validates and freezes its public properties

    Code
      provenance@producer <- "other"
    Condition
      Error:
      ! Can't set read-only property <graft::GraftProvenance>@producer

# graft provenance rejects malformed inputs

    Code
      graft_provenance("")
    Condition
      Error in `batch_scalar()`:
      ! `producer` must be one non-empty string.

---

    Code
      graft_provenance("workflow", run_id = "")
    Condition
      Error in `graft_optional_string()`:
      ! `run_id` must be one non-empty string or `NULL`.

---

    Code
      graft_provenance("workflow", metadata = data.frame(x = 1))
    Condition
      Error in `graft_provenance()`:
      ! `metadata` must be a JSON-serializable list.

# graft provenance is revalidated at API boundaries

    Code
      graft:::as_graft_provenance(tampered, "provenance")
    Condition
      Error in `graft:::as_graft_provenance()`:
      ! `provenance` is an invalid GraftProvenance object; create a new one.
      Caused by error:
      ! <graft::GraftProvenance> object is invalid:
      - @producer must be one non-empty string

---

    Code
      graft:::provenance_batch(tampered, "batch-id")
    Condition
      Error in `as_graft_provenance()`:
      ! `provenance` is an invalid GraftProvenance object; create a new one.
      Caused by error:
      ! <graft::GraftProvenance> object is invalid:
      - @producer must be one non-empty string

