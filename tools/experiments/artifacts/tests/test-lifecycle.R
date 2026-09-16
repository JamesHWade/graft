test_that("both compositions retain bytes, full selections and history across processes", {
  for (backend in c("manifest", "graft")) {
    root <- withr::local_tempdir()
    run <- function(action) {
      callr::r(
        function(checkout, root, backend, action) {
          source(file.path(checkout, "tools/experiments/artifacts/fixture.R"))
          artifact_process(checkout, root, backend, action)
        },
        args = list(artifact_checkout, root, backend, action),
        libpath = .libPaths()
      )
    }
    original <- run("produce")
    unchanged <- run("consume")
    revised <- run("revise")
    expect_length(unique(c(original$pid, unchanged$pid, revised$pid)), 3L)
    expect_identical(original$hashes, unchanged$hashes)
    expect_identical(original$hashes, revised$hashes)
    expect_identical(original$selection, unchanged$selection)
    expect_identical(original$selection, revised$selection)
    expect_length(original$selection, 5L)
    expect_identical(unchanged$changed, character())
    expect_setequal(
      revised$changed,
      c(
        "artifact:source",
        "artifact:evidence",
        "artifact:figure",
        "artifact:report"
      )
    )
    expect_identical(original$report, revised$report)
    expect_match(original$report, "Observed mean: 2", fixed = TRUE)
    expect_identical(
      any(vapply(
        original$selection,
        function(ref) ref$id == "artifact:draft",
        logical(1)
      )),
      FALSE
    )
    expect_length(unchanged$index, 6L)
  }
})

test_that("saving drafts does not authorize consultation and withdrawal preserves inspection", {
  for (backend in c("manifest", "graft")) {
    store <- local_artifact_store(backend)
    refs <- artifact_fixture(store)
    expect_identical(file.exists(file.path(store$root, "policy.json")), FALSE)
    basis <- artifact_approve(store, list(refs$report), "later synthesis")
    expect_error(
      artifact_read_basis(store, basis, "unrelated purpose"),
      class = "artifact_experiment_error"
    )
    before <- artifact_read_basis(store, basis, "later synthesis")
    expect_equal(nrow(artifact_preview(store, refs$evidence)), 2L)
    expect_lte(nchar(artifact_preview(store, refs$report, 20L)), 20L)
    expect_identical(
      artifact_preview(store, refs$figure)$media_type,
      "image/png"
    )
    artifact_revoke(store, basis)
    expect_error(
      artifact_read_basis(store, basis, "later synthesis"),
      class = "artifact_experiment_error"
    )
    expect_identical(artifact_read_basis(store, basis, consult = FALSE), before)
    expect_identical(
      artifact_approve(store, list(refs$report), "later synthesis"),
      basis
    )
    expect_identical(
      artifact_read_basis(store, basis, "later synthesis"),
      before
    )
    index <- artifact_index(store)
    cache <- file.path(store$root, "search-cache.json")
    writeLines(artifact_json(index), cache)
    unlink(cache)
    expect_identical(artifact_index(store), index)
  }
})

test_that("partial publication and identical retry never lose earlier content", {
  for (backend in c("manifest", "graft")) {
    store <- local_artifact_store(backend)
    input <- withr::local_tempfile()
    writeLines("original", input)
    expect_error(
      artifact_save(
        store,
        "artifact:report",
        input,
        "text/markdown",
        fail_after_bytes = TRUE
      ),
      class = "artifact_experiment_error"
    )
    expect_null(artifact_current(store, "artifact:report"))
    expect_length(list.files(file.path(store$root, "content")), 1L)
    original <- artifact_save(store, "artifact:report", input, "text/markdown")
    expect_identical(
      artifact_save(store, "artifact:report", input, "text/markdown"),
      original
    )
    writeLines("correction", input)
    corrected <- artifact_save(store, "artifact:report", input, "text/markdown")
    expect_identical(
      rawToChar(artifact_resolve(store, original)$bytes),
      "original\n"
    )
    expect_identical(
      rawToChar(artifact_resolve(store, corrected)$bytes),
      "correction\n"
    )
    writeLines("stale proposal", input)
    expect_error(
      artifact_save(
        store,
        "artifact:report",
        input,
        "text/markdown",
        expected = original
      ),
      class = "artifact_experiment_error"
    )
    expect_identical(artifact_current(store, "artifact:report"), corrected)
    # The producer's mutable file is not the retained object.
    unlink(input)
    expect_identical(
      rawToChar(artifact_resolve(store, original)$bytes),
      "original\n"
    )
  }
})

test_that("missing, corrupt or mismatched content fails instead of substituting latest", {
  for (backend in c("manifest", "graft")) {
    store <- local_artifact_store(backend)
    input <- withr::local_tempfile()
    writeLines("preserved", input)
    ref <- artifact_save(store, "artifact:report", input, "text/markdown")
    item <- artifact_resolve(store, ref)
    path <- artifact_digest_path(store$root, "content", item$metadata$payload)
    writeBin(charToRaw("corrupted"), path)
    expect_error(
      artifact_resolve(store, ref),
      class = "artifact_experiment_error"
    )
    expect_error(
      artifact_save(store, "artifact:report", input, "text/markdown"),
      class = "artifact_experiment_error"
    )
    unlink(path)
    expect_error(
      artifact_resolve(store, ref),
      class = "artifact_experiment_error"
    )
    expect_error(
      artifact_resolve(store, list(id = ref$id, revision = "../escape")),
      class = "artifact_experiment_error"
    )
    expect_error(
      artifact_save(store, "artifact:other", input, "application/x-r-rds"),
      class = "artifact_experiment_error"
    )
  }
})

test_that("lost acknowledgment retries reuse committed metadata and detect incomplete bases", {
  for (backend in c("manifest", "graft")) {
    store <- local_artifact_store(backend)
    input <- withr::local_tempfile()
    writeLines("retained dependency", input)
    expect_error(
      artifact_save(
        store,
        "artifact:input",
        input,
        "text/markdown",
        fail_after_publish = TRUE
      ),
      class = "artifact_experiment_error"
    )
    published <- artifact_current(store, "artifact:input")
    expect_identical(
      artifact_save(store, "artifact:input", input, "text/markdown"),
      published
    )
    if (backend == "graft") {
      expect_equal(
        nrow(graft::graft_history(store$connection, "artifact:input")),
        1L
      )
    } else {
      expect_length(list.files(file.path(store$root, "manifests")), 1L)
    }
    writeLines("derived report", input)
    root <- artifact_save(
      store,
      "artifact:report",
      input,
      "text/markdown",
      list(published)
    )
    basis <- artifact_approve(store, list(root), "reuse")
    incomplete <- artifact_read_json(artifact_digest_path(
      store$root,
      "selections",
      basis
    ))
    incomplete$selection <- incomplete$selection[1L]
    forged <- charToRaw(artifact_json(incomplete))
    forged_id <- artifact_hash(forged)
    artifact_write(
      forged,
      artifact_digest_path(store$root, "selections", forged_id)
    )
    expect_error(
      artifact_read_basis(store, forged_id, consult = FALSE),
      class = "artifact_experiment_error"
    )
    writeBin(as.raw(rep(1L, 1024^2 + 1L)), input)
    expect_error(
      artifact_save(store, "artifact:oversized", input, "text/markdown"),
      class = "artifact_experiment_error"
    )
    expect_null(artifact_current(store, "artifact:oversized"))
  }
})

test_that("save verifies transitive content before it publishes any new metadata", {
  for (backend in c("manifest", "graft")) {
    store <- local_artifact_store(backend)
    input <- withr::local_tempfile()
    writeLines("source", input)
    a <- artifact_save(store, "artifact:source", input, "text/markdown")
    b <- artifact_save(
      store,
      "artifact:derived",
      input,
      "text/markdown",
      list(a)
    )
    payload <- artifact_resolve(store, a)$metadata$payload
    path <- artifact_digest_path(store$root, "content", payload)
    # Give B its own retained content so only the transitive ancestor is broken.
    writeLines("derived", input)
    b <- artifact_save(
      store,
      "artifact:derived",
      input,
      "text/markdown",
      list(a)
    )
    writeBin(charToRaw("broken"), path)
    expect_error(
      artifact_save(store, "artifact:report", input, "text/markdown", list(b)),
      class = "artifact_experiment_error"
    )
    expect_null(artifact_current(store, "artifact:report"))
    unlink(path)
    expect_error(
      artifact_save(store, "artifact:report", input, "text/markdown", list(b)),
      class = "artifact_experiment_error"
    )
    expect_null(artifact_current(store, "artifact:report"))
  }
})

test_that("both current indexes reject a new identity before exceeding capacity", {
  for (backend in c("manifest", "graft")) {
    store <- local_artifact_store(backend)
    expect_identical(store$capacity, 50L)
    store$capacity <- 2L
    input <- withr::local_tempfile()
    writeLines("same payload", input)
    first <- artifact_save(store, "artifact:one", input, "text/markdown")
    artifact_save(store, "artifact:two", input, "text/markdown")
    expect_error(
      artifact_save(store, "artifact:three", input, "text/markdown"),
      class = "artifact_experiment_error"
    )
    expect_length(artifact_all_current(store), 2L)
    expect_null(artifact_current(store, "artifact:three"))
    expect_identical(
      artifact_save(store, "artifact:one", input, "text/markdown"),
      first
    )
    writeLines("revision within capacity", input)
    changed <- artifact_save(store, "artifact:one", input, "text/markdown")
    expect_identical(artifact_current(store, "artifact:one"), changed)
  }
})
