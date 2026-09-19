test_that("manifest captures a complete local artifact store deterministically", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  source <- graft_artifact_save(
    store,
    "source",
    charToRaw("evidence"),
    "text/plain"
  )
  report <- graft_artifact_save(
    store,
    "report",
    charToRaw("report"),
    "text/plain",
    dependencies = list(source)
  )
  selection <- graft_artifact_select(store, list(report))
  graft_artifact_decide(
    store,
    "subject",
    "review",
    expected = NULL,
    selection = selection,
    action = "accept",
    actor = "reviewer",
    reason = "reviewed",
    purpose = "research"
  )

  manifest <- graft_artifact_manifest(store)

  expect_identical(manifest$format, "graft-artifact-manifest/1")
  expect_match(manifest$id, "^[0-9a-f]{64}$")
  expect_length(
    Filter(\(x) x$kind == "store", manifest$objects),
    0L
  )
  expect_length(manifest$objects, 6L)
  expect_equal(
    vapply(
      manifest$objects,
      \(x) paste(x$kind, x$key, sep = "\n"),
      character(1)
    ),
    sort(vapply(
      manifest$objects,
      \(x) paste(x$kind, x$key, sep = "\n"),
      character(1)
    ))
  )
  expect_identical(
    vapply(
      manifest$objects,
      \(x) identical(x$kind, "content") && identical(x$key, x$digest),
      logical(1)
    ),
    c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE)
  )
})

test_that("manifest permits valid orphan content and excludes the marker", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  graft_artifact_save(store, "kept", charToRaw("kept"), "text/plain")
  orphan <- charToRaw("orphan")
  orphan_digest <- digest::digest(orphan, algo = "sha256", serialize = FALSE)
  dir.create(file.path(store$path, "content"), showWarnings = FALSE)
  writeBin(orphan, file.path(store$path, "content", orphan_digest))

  manifest <- graft_artifact_manifest(store)

  expect_length(
    Filter(
      \(x) identical(x$kind, "content") && identical(x$key, orphan_digest),
      manifest$objects
    ),
    1L
  )
  expect_length(
    Filter(\(x) x$key == "store.json", manifest$objects),
    0L
  )
})

test_that("manifest rejects unknown entries and corrupt content", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  ref <- graft_artifact_save(store, "kept", charToRaw("kept"), "text/plain")
  writeLines("unknown", file.path(store$path, "unknown.txt"))
  expect_error(graft_artifact_manifest(store), class = "graft_artifact_error")
  unlink(file.path(store$path, "unknown.txt"))

  payload <- graft_artifact_read(store, ref)$metadata$payload
  writeBin(charToRaw("changed"), file.path(store$path, "content", payload))
  expect_error(graft_artifact_manifest(store), class = "graft_artifact_error")
})

test_that("manifest bounds are checked before payload reads", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  graft_artifact_save(store, "kept", charToRaw("kept"), "text/plain")
  expect_error(
    graft_artifact_manifest(store, max_objects = 0),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_artifact_manifest(store, max_objects = 1),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_artifact_manifest(store, max_total_bytes = 1),
    class = "graft_artifact_error"
  )
})

test_that("empty stores have a stable empty manifest", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  dir.create(file.path(store$path, "content"))
  dir.create(file.path(store$path, "revisions"))
  dir.create(file.path(store$path, "selections"))
  dir.create(file.path(store$path, "decisions"))
  manifest <- graft_artifact_manifest(store)

  expect_identical(manifest$objects, list())
  expect_match(manifest$id, "^[0-9a-f]{64}$")
  expect_identical(graft_artifact_manifest(store), manifest)
})

test_that("incomplete decision directories are rejected", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  stream <- file.path(store$path, "decisions", strrep("a", 64))
  dir.create(stream, recursive = TRUE)
  expect_error(
    graft_artifact_manifest(store),
    class = "graft_artifact_error"
  )
})

test_that("staging and dangling links are rejected before reads", {
  skip_on_os("windows")
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  stream <- file.path(store$path, "decisions", strrep("a", 64))
  dir.create(stream, recursive = TRUE)
  writeBin(charToRaw("partial"), file.path(stream, "staged-interrupted"))
  expect_error(
    graft_artifact_manifest(store),
    class = "graft_artifact_error"
  )

  unlink(file.path(store$path, "decisions"), recursive = TRUE)
  content <- file.path(store$path, "content")
  dir.create(content)
  linked <- file.path(content, strrep("b", 64))
  expect_identical(file.symlink("missing-content", linked), TRUE)
  expect_error(
    graft_artifact_manifest(store),
    class = "graft_artifact_error"
  )
})

test_that("a nonregular marker is rejected without opening it", {
  skip_on_os("windows")
  skip_if(!nzchar(Sys.which("mkfifo")))
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  marker <- file.path(store$path, "store.json")
  unlink(marker)
  expect_identical(system2("mkfifo", shQuote(marker)), 0L)
  expect_error(
    graft_artifact_manifest(store),
    class = "graft_artifact_error"
  )
})

test_that("missing revision dependencies reject the complete inventory", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  source <- graft_artifact_save(
    store,
    "source",
    charToRaw("source"),
    "text/plain"
  )
  graft_artifact_save(
    store,
    "report",
    charToRaw("report"),
    "text/plain",
    dependencies = list(source)
  )
  unlink(file.path(store$path, "revisions", source$revision))
  expect_error(
    graft_artifact_manifest(store),
    class = "graft_artifact_error"
  )
})

test_that("decision history cannot certify without every historical selection", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  ref <- graft_artifact_save(store, "report", charToRaw("report"), "text/plain")
  selection <- graft_artifact_select(store, list(ref))
  graft_artifact_decide(
    store,
    "subject",
    "review",
    expected = NULL,
    selection = selection,
    action = "accept",
    actor = "reviewer",
    reason = "reviewed",
    purpose = "research"
  )
  corrected <- graft_artifact_save(
    store,
    "report",
    charToRaw("corrected"),
    "text/plain"
  )
  current <- graft_artifact_select(store, list(corrected))
  graft_artifact_decide(
    store,
    "subject",
    "correction",
    expected = graft_artifact_read_decision(store, "subject")$id,
    selection = current,
    action = "accept",
    actor = "reviewer",
    reason = "corrected",
    purpose = "research"
  )
  unlink(file.path(store$path, "selections", selection))
  expect_identical(graft_artifact_read_selection(store, current)$id, current)
  expect_error(
    graft_artifact_manifest(store),
    class = "graft_artifact_error"
  )
})

test_that("dangling links in fixed kind paths cannot hide an object set", {
  skip_on_os("windows")
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  expect_identical(
    file.symlink("missing-directory", file.path(store$path, "content")),
    TRUE
  )
  expect_error(graft_artifact_manifest(store), class = "graft_artifact_error")
})

test_that("deep dependency chains validate without using the R call stack", {
  refs <- lapply(seq_len(4900L), function(i) {
    list(id = as.character(i), revision = sprintf("%064x", i))
  })
  artifacts <- lapply(seq_along(refs), function(i) {
    list(
      ref = refs[[i]],
      metadata = list(
        dependencies = if (i < length(refs)) {
          list(refs[[i + 1L]])
        } else {
          list()
        }
      )
    )
  })
  expect_null(artifact_recovery_check_dependencies(artifacts))
})
