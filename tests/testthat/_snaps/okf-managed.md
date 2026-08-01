# synchronization exposes current, modified, and stale states

    Code
      kg_okf_context(fixture$store)
    Condition
      Error in `kg_okf_context()`:
      ! Accepted OKF context requires a current bundle; status is `stale`. The store has accepted changes since the last synchronization.

# selected and historical exports cannot replace the managed tree

    Code
      kg_export_okf(fixture$store, classes = "Entity", overwrite = TRUE)
    Condition
      Error in `kg_export_okf()`:
      ! The managed OKF directory must remain a complete projection of current accepted state. Supply a different `path` for selected or historical exports.

---

    Code
      kg_export_okf(fixture$store, as_of = fixture$result$batch_id, overwrite = TRUE)
    Condition
      Error in `kg_export_okf()`:
      ! The managed OKF directory must remain a complete projection of current accepted state. Supply a different `path` for selected or historical exports.

# OKF import plans reject deletion and post-review changes

    Code
      kg_apply_okf_import(fixture$store, plan, kg_batch("human:reviewer"))
    Condition
      Error in `kg_apply_okf_import()`:
      ! The store or edited OKF bundle changed after planning. Create and review a new import plan.

---

    Code
      kg_plan_okf_import(fixture$store)
    Condition
      Error in `kg_plan_okf_import()`:
      ! Removing OKF concept files is not supported; restore 1 accepted concept(s) before planning.
