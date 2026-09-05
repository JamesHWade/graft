test_that("both consumers retain complete exact selections across acceptance cycles", {
  example <- reuse_example()
  for (consumer in c("research", "reading")) {
    local({
      store <- local_narrative_store()
      basis <- capture_consumer_basis(store, consumer)
      values <- example$read_reuse_basis(store, basis, \(ids) TRUE)
      expect_length(values, if (consumer == "research") 3L else 4L)
      unchanged <- example$review_reuse_basis(store, basis)
      expect_equal(nrow(unchanged$changes), 0L)
      expect_identical(unchanged$needs_review, character())
      for (cycle in seq_len(2L)) {
        source <- narrative_fixture()$narrative_records()$source
        source$quote <- paste("Accepted evidence correction", cycle)
        graft_ingest(
          store,
          list(source = source),
          graft_provenance(
            "research",
            idempotency_key = paste0("cycle-", cycle)
          )
        )
        expect_identical(
          example$read_reuse_basis(store, basis, \(ids) TRUE),
          values
        )
        assessment <- example$review_reuse_basis(store, basis)
        expect_identical(assessment$changes$record_id, "source:trial-v1")
        expect_identical(
          assessment$needs_review,
          if (consumer == "research") {
            "knowledge:conclusion"
          } else {
            "knowledge:interpretation"
          }
        )
        # Explicit host refresh preserves the complete set, not only changed IDs.
        refreshed <- capture_consumer_basis(store, consumer)
        expect_identical(refreshed$records$record_id, basis$records$record_id)
        expect_equal(
          nrow(example$review_reuse_basis(store, refreshed)$changes),
          0L
        )
      }
      expect_identical(
        graft_get(store, basis$roots[[1L]])$record,
        values[[basis$roots[[1L]]]]
      )
    })
  }
})

test_that("a selected deleted support remains visible without its parent payload", {
  example <- reuse_example()
  for (consumer in c("research", "reading")) {
    local({
      store <- local_narrative_store()
      basis <- capture_consumer_basis(store, consumer)
      original <- example$read_reuse_basis(store, basis, \(ids) TRUE)
      support <- if (consumer == "research") {
        "support:conclusion"
      } else {
        "support:interpretation"
      }
      append_reuse_tombstone(store, support)
      view <- graft_at(store, graft_snapshot(store))
      changes <- graft_changes(
        view,
        since = basis$snapshot,
        record_ids = support,
        limit = 1L
      )
      expect_identical(changes$action, "delete")
      expect_null(changes$record[[1L]])
      expect_identical(attr(changes, "truncated"), FALSE)
      assessment <- example$review_reuse_basis(view, basis)
      expect_identical(assessment$needs_review, basis$roots[[1L]])
      expect_identical(
        example$read_reuse_basis(store, basis, \(ids) TRUE),
        original
      )
      expect_error(graft_get(view, support), class = "graft_reference_error")
      selection <- reuse_consumer_selection(consumer)
      expect_error(
        example$capture_reuse_basis(
          store,
          selection$roots,
          selection$dependencies
        ),
        class = "graft_reference_error"
      )
    })
  }
})

test_that("trusted checkpoints rebind complete selections in a fresh process", {
  path <- withr::local_tempfile(fileext = ".duckdb")
  store <- local_narrative_store(path)
  basis <- capture_consumer_basis(store)
  expected <- reuse_example()$read_reuse_basis(store, basis, \(ids) TRUE)
  checkpoint <- withr::local_tempfile(fileext = ".rds")
  saveRDS(basis, checkpoint)
  graft_close(store)
  result <- callr::r(
    function(checkout, path, checkpoint) {
      pkgload::load_all(checkout, quiet = TRUE)
      example <- new.env()
      sys.source(
        system.file("examples/reuse-basis.R", package = "graft"),
        example
      )
      store <- graft::graft_open(
        graft::graft_schema(system.file(
          "extdata/narrative-knowledge.data-dict.json",
          package = "graft"
        )),
        path,
        read_only = TRUE,
        okf = "disabled"
      )
      on.exit(graft::graft_close(store))
      example$read_reuse_basis(store, readRDS(checkpoint), \(ids) TRUE)
    },
    args = list(
      checkout = normalizePath(test_path("../..")),
      path = path,
      checkpoint = checkpoint
    )
  )
  expect_identical(result, expected)
})

test_that("incomplete, incompatible and inaccessible checkpoints fail as a whole", {
  example <- reuse_example()
  store <- local_narrative_store()
  basis <- capture_consumer_basis(store)
  partial <- basis
  partial$records <- partial$records[-1L, ]
  expect_snapshot(
    error = TRUE,
    example$read_reuse_basis(store, partial, \(ids) TRUE)
  )
  altered <- basis
  altered$records$revision_id[[1L]] <- "missing"
  expect_snapshot(
    error = TRUE,
    example$read_reuse_basis(store, altered, \(ids) TRUE)
  )
  expect_snapshot(
    error = TRUE,
    example$read_reuse_basis(store, basis, \(ids) FALSE)
  )
  expect_error(
    example$read_reuse_basis(local_narrative_store(), basis, function(ids) {
      TRUE
    }),
    class = "graft_snapshot_error"
  )
  invalid_snapshot <- basis
  data <- attr(invalid_snapshot$snapshot, ".data", exact = TRUE)
  data$schema_build_digest <- "sha256:incompatible"
  attr(invalid_snapshot$snapshot, ".data") <- data
  expect_error(
    example$read_reuse_basis(store, invalid_snapshot, \(ids) TRUE),
    class = "graft_snapshot_error"
  )
  expect_snapshot(
    error = TRUE,
    example$reuse_ids(paste0("id-", seq_len(1001L)))
  )
  selection <- reuse_consumer_selection("reading")
  expect_error(
    example$capture_reuse_basis(store, "missing", selection$dependencies),
    class = "graft_reference_error"
  )
})

test_that("empty selections are explicit and never materialize ambient knowledge", {
  store <- local_narrative_store()
  example <- reuse_example()
  basis <- example$capture_reuse_basis(
    store,
    character(),
    data.frame(outcome = character(), dependency = character())
  )
  expect_length(example$read_reuse_basis(store, basis, \(ids) TRUE), 0L)
  expect_equal(nrow(example$review_reuse_basis(store, basis)$changes), 0L)
})
