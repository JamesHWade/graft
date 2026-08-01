# market planner requires an ISO action due date

    Code
      environment$mi_run_planner(environment$mi_reference_planner(bundle), bundle$
        suggested_request, bundle, "No accepted market assessments yet.")
    Condition
      Error in `mi_iso_date()`:
      ! `planner$due_date` must be a valid ISO date (YYYY-MM-DD).
