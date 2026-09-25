test_that("graft_blob() stores bytes once under their digest", {
  store <- local_artifact_store()
  first <- graft_blob(store, tiny_png(), "image/png")
  second <- graft_blob(store, tiny_png(), "image/png")

  hex <- digest::digest(tiny_png(), algo = "sha256", serialize = FALSE)
  expect_identical(first, second)
  expect_identical(first$id, paste0("sha256:", hex))
  expect_identical(first$size_bytes, as.double(length(tiny_png())))
  root <- graft:::as_graft_store_internal(store)$blob_path
  expect_identical(
    list.files(root, recursive = TRUE),
    file.path(substr(hex, 1, 2), hex)
  )
})

test_that("a kept artifact commits with its blob and reads back with history", {
  store <- local_artifact_store()
  blob <- graft_blob(store, tiny_png(), "image/png")
  plan <- graft_plan(store, kept_artifact_records(blob), blob_test_provenance())
  expect_identical(plan@valid, TRUE)
  graft_commit(store, plan)

  expect_identical(graft_blob_read(store, blob$id), tiny_png())

  retitled <- kept_artifact_records(blob, title = "Cure conversion, lot 22B")
  graft_ingest(store, retitled, blob_test_provenance("keep-2"))
  history <- graft_history(store, "artifact:cure:conv-7:card-12")
  expect_equal(nrow(history), 2L)
  expect_identical(
    graft_get(
      store,
      "artifact:cure:conv-7:card-12",
      include = character()
    )$record$title,
    "Cure conversion, lot 22B"
  )
})

test_that("planning reports missing, altered, and mislabelled blob bytes", {
  store <- local_artifact_store()
  blob <- graft_blob(store, tiny_png(), "image/png")
  path <- file.path(
    graft:::as_graft_store_internal(store)$blob_path,
    substr(sub("sha256:", "", blob$id), 1, 2),
    sub("sha256:", "", blob$id)
  )

  wrong_size <- blob
  wrong_size$size_bytes <- 1
  plan <- graft_plan(
    store,
    kept_artifact_records(wrong_size),
    blob_test_provenance()
  )
  expect_identical(plan@issues$rule, "blob_size")

  writeBin(rev(tiny_png()), path)
  plan <- graft_plan(store, kept_artifact_records(blob), blob_test_provenance())
  expect_identical(plan@issues$rule, "blob_digest")

  unlink(path)
  plan <- graft_plan(store, kept_artifact_records(blob), blob_test_provenance())
  expect_identical(plan@issues$rule, "blob_missing")
  expect_identical(plan@issues$condition_class, "graft_blob_error")

  bad_id <- blob
  bad_id$id <- "png-1"
  records <- kept_artifact_records(bad_id)
  plan <- graft_plan(
    store,
    list(graft_blob = records$graft_blob),
    blob_test_provenance()
  )
  expect_identical(plan@issues$rule, "blob_id")
})

test_that("a committed blob cannot change", {
  store <- local_artifact_store()
  blob <- graft_blob(store, tiny_png(), "image/png")
  graft_ingest(store, list(graft_blob = blob), blob_test_provenance())

  relabelled <- blob
  relabelled$media_type <- "image/gif"
  plan <- graft_plan(
    store,
    list(graft_blob = relabelled),
    blob_test_provenance("k2")
  )
  expect_identical(plan@issues$rule, "blob_immutable")
})

test_that("a version cannot reference a blob that was never staged", {
  store <- local_artifact_store()
  blob <- graft_blob(store, tiny_png(), "image/png")
  records <- kept_artifact_records(blob)
  records$graft_blob <- NULL
  plan <- graft_plan(store, records, blob_test_provenance())
  expect_identical(plan@valid, FALSE)
  expect_contains(plan@issues$field, "blob_id")
})

test_that("graft_commit() rechecks blob bytes planned earlier", {
  store <- local_artifact_store()
  blob <- graft_blob(store, tiny_png(), "image/png")
  plan <- graft_plan(store, kept_artifact_records(blob), blob_test_provenance())
  unlink(list.files(
    graft:::as_graft_store_internal(store)$blob_path,
    recursive = TRUE,
    full.names = TRUE
  ))
  expect_error(graft_commit(store, plan), class = "graft_blob_error")
})

test_that("graft_blob_read() refuses uncommitted and corrupted blobs", {
  store <- local_artifact_store()
  blob <- graft_blob(store, tiny_png(), "image/png")
  expect_error(graft_blob_read(store, blob$id), class = "graft_reference_error")

  graft_ingest(store, list(graft_blob = blob), blob_test_provenance())
  path <- list.files(
    graft:::as_graft_store_internal(store)$blob_path,
    recursive = TRUE,
    full.names = TRUE
  )
  writeBin(rev(tiny_png()), path)
  expect_error(graft_blob_read(store, blob$id), class = "graft_blob_error")
  expect_error(
    graft_blob_read(store, "png-1"),
    class = "graft_validation_error"
  )
})

test_that("graft_blob() needs a contract with a well-formed graft_blob table", {
  schema <- graft_schema(system.file(
    "extdata",
    "team-directory.data-dict.json",
    package = "graft",
    mustWork = TRUE
  ))
  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))
  expect_error(
    graft_blob(store, tiny_png(), "image/png"),
    class = "graft_schema_error"
  )

  artifacts <- graft_schema(system.file(
    "extdata",
    "artifacts.data-dict.json",
    package = "graft",
    mustWork = TRUE
  ))
  manifest <- graft:::as_graft_schema_internal(artifacts)$manifest
  manifest$slots[["graft_blob.size_bytes"]]$range <- "string"
  expect_error(
    graft:::validate_blob_contract(manifest),
    class = "graft_schema_error"
  )
})

test_that("graft_blob() validates its inputs", {
  store <- local_artifact_store()
  expect_error(
    graft_blob(store, 1:3, "image/png"),
    class = "graft_validation_error"
  )
  expect_error(
    graft_blob(store, tiny_png(), "png"),
    class = "graft_validation_error"
  )
})

test_that("an in-memory store keeps blobs in a temporary directory", {
  schema <- graft_schema(system.file(
    "extdata",
    "artifacts.data-dict.json",
    package = "graft",
    mustWork = TRUE
  ))
  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))
  blob <- graft_blob(store, tiny_png(), "image/png")
  graft_ingest(store, list(graft_blob = blob), blob_test_provenance())
  expect_identical(graft_blob_read(store, blob$id), tiny_png())
})
