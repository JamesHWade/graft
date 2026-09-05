# Offline teaching data. Applications own their schemas and authorization.
narrative_records <- function() {
  list(
    knowledge = data.frame(
      id = c(
        "knowledge:conclusion",
        "knowledge:interpretation",
        "knowledge:preference",
        "knowledge:question"
      ),
      kind = c("conclusion", "interpretation", "preference", "question"),
      purpose = c(
        "research synthesis",
        "reading interpretation",
        "reading selection",
        "future investigation"
      ),
      body = c(
        "## Research conclusion\n\nThe synthetic trial reports a lower temperature—uncertainty remains.",
        "## Reading interpretation\n\nThe café report suggests a local effect, not a universal result.",
        "Prefer short reading sessions in the morning; this is a preference, not source evidence.",
        "Would the result survive a larger trial? This remains an unresolved question."
      ),
      lifecycle = rep("active", 4L),
      tags = I(list(
        c("research", "synthetic"),
        "reading",
        "reading",
        "research"
      )),
      owner_binding = rep("synthetic-reader-private", 4L)
    ),
    source = data.frame(
      id = "source:trial-v1",
      document_revision = "document:synthetic-trial:version-1",
      quote = "The synthetic trial reports a lower temperature."
    ),
    support = data.frame(
      id = c("support:conclusion", "support:interpretation"),
      knowledge_id = c("knowledge:conclusion", "knowledge:interpretation"),
      source_id = rep("source:trial-v1", 2L),
      anchor = rep("paragraph:1", 2L)
    )
  )
}

# Run inside a function so connections close even after an error.
narrative_example <- function() {
  schema <- graft::graft_schema(system.file(
    "extdata/narrative-knowledge.data-dict.json",
    package = "graft",
    mustWork = TRUE
  ))
  store <- graft::graft_open(schema, okf = "disabled")
  on.exit(graft::graft_close(store))
  records <- narrative_records()
  invalid <- records
  invalid$support$source_id[[1L]] <- "source:missing"
  rejected <- graft::graft_plan(
    store,
    invalid,
    graft::graft_provenance("teaching-host", idempotency_key = "invalid")
  )
  stopifnot(!rejected@valid)
  plan <- graft::graft_plan(
    store,
    records,
    graft::graft_provenance("teaching-host", idempotency_key = "accepted-1")
  )
  stopifnot(plan@valid)
  # This offline script is the host's explicit acceptance of synthetic data.
  graft::graft_commit(store, plan)
  snapshot <- graft::graft_snapshot(store)
  view <- graft::graft_at(store, snapshot)
  before <- graft::graft_get(view, "knowledge:interpretation")
  corrected <- records$knowledge[2L, , drop = FALSE]
  corrected$body <- "The synthetic report supports only a preliminary interpretation."
  graft::graft_ingest(
    store,
    list(knowledge = corrected),
    graft::graft_provenance("teaching-host", idempotency_key = "correction-1")
  )
  stopifnot(identical(graft::graft_get(view, before$id), before))
  list(
    rejected = rejected@issues,
    pinned = before$record,
    current = graft::graft_get(store, before$id)$record,
    history = graft::graft_history(store, before$id)
  )
}
