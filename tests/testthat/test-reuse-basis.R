test_that("dependency changes flag affected roots and retain complete selections", {
  example <- reuse_example()
  store <- local_narrative_store()
  roots <- c(
    "knowledge:conclusion",
    "knowledge:interpretation",
    "knowledge:preference"
  )
  dependencies <- rbind(
    reuse_consumer_selection("research")$dependencies,
    reuse_consumer_selection("reading")$dependencies
  )
  basis <- example$capture_reuse_basis(store, roots, dependencies)
  values <- example$read_reuse_basis(store, basis, \(ids) TRUE)
  expect_length(values, 6L)
  expect_identical(
    example$review_reuse_basis(store, basis)$needs_review,
    character()
  )
  for (cycle in seq_len(2L)) {
    source <- narrative_fixture()$narrative_records()$source
    source$quote <- paste("Accepted evidence correction", cycle)
    graft_ingest(
      store,
      list(source = source),
      graft_provenance("research", idempotency_key = paste0("cycle-", cycle))
    )
    expect_identical(
      example$read_reuse_basis(store, basis, \(ids) TRUE),
      values
    )
    assessment <- example$review_reuse_basis(store, basis)
    expect_identical(assessment$changes$record_id, "source:trial-v1")
    expect_identical(assessment$needs_review, roots[1:2])
    refreshed <- example$capture_reuse_basis(store, roots, dependencies)
    expect_identical(refreshed$records$record_id, basis$records$record_id)
    expect_equal(nrow(example$review_reuse_basis(store, refreshed)$changes), 0L)
  }
})

test_that("a selected deleted support is visible in both live and pinned changes", {
  example <- reuse_example()
  store <- local_narrative_store()
  basis <- capture_consumer_basis(store)
  original <- example$read_reuse_basis(store, basis, \(ids) TRUE)
  support <- "support:interpretation"
  append_test_tombstone(store, support)
  view <- graft_at(store, graft_snapshot(store))
  changes <- graft_changes(
    store,
    since = basis$snapshot,
    record_ids = support,
    limit = 1L
  )
  expect_identical(
    changes,
    graft_changes(
      view,
      since = basis$snapshot,
      record_ids = support,
      limit = 1L
    )
  )
  expect_identical(changes$action, "delete")
  expect_null(changes$record[[1L]])
  expect_identical(attr(changes, "truncated"), FALSE)
  expect_identical(
    example$review_reuse_basis(store, basis)$needs_review,
    "knowledge:interpretation"
  )
  expect_identical(
    example$read_reuse_basis(store, basis, \(ids) TRUE),
    original
  )
  expect_error(graft_get(store, support), class = "graft_reference_error")
  expect_error(graft_get(view, support), class = "graft_reference_error")
  expect_error(capture_consumer_basis(store), class = "graft_reference_error")
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
      if (!is.null(checkout)) {
        pkgload::load_all(checkout, quiet = TRUE)
      }
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
      basis <- readRDS(checkpoint)
      view <- graft::graft_at(store, basis$snapshot)
      list(
        values = example$read_reuse_basis(store, basis, \(ids) TRUE),
        revisions = vapply(
          basis$records$record_id,
          function(id) {
            graft::graft_history(view, id, limit = 1L)$revision_id[[1L]]
          },
          character(1),
          USE.NAMES = FALSE
        )
      )
    },
    args = list(
      checkout = if (pkgload::is_dev_package("graft")) {
        normalizePath(test_path("../.."))
      } else {
        NULL
      },
      path = path,
      checkpoint = checkpoint
    )
  )
  expect_identical(result$values, expected)
  expect_identical(result$revisions, basis$records$revision_id)
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

test_that("dependency traversal enforces its bound before reading a store", {
  example <- reuse_example()
  dependencies <- data.frame(
    outcome = "root",
    dependency = paste0("id-", seq_len(1000L))
  )
  expect_length(example$reuse_closure("root", dependencies[-1L, ]), 1000L)
  expect_snapshot(
    error = TRUE,
    example$capture_reuse_basis(NULL, "root", dependencies)
  )
  cyclic <- data.frame(outcome = c("a", "b"), dependency = c("b", "a"))
  expect_snapshot(error = TRUE, example$capture_reuse_basis(NULL, "a", cyclic))
})
