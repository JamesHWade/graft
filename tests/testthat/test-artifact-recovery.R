test_that("manifest captures a complete local artifact store deterministically", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  source <- artifact_save(
    store,
    "source",
    charToRaw("evidence"),
    "text/plain"
  )
  report <- artifact_save(
    store,
    "report",
    charToRaw("report"),
    "text/plain",
    dependencies = list(source)
  )
  selection <- artifact_select(store, list(report))
  artifact_decide(
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

  manifest <- graft_manifest(store)

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
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  artifact_save(store, "kept", charToRaw("kept"), "text/plain")
  orphan <- charToRaw("orphan")
  orphan_digest <- digest::digest(orphan, algo = "sha256", serialize = FALSE)
  dir.create(file.path(store@path, "content"), showWarnings = FALSE)
  writeBin(orphan, file.path(store@path, "content", orphan_digest))

  manifest <- graft_manifest(store)

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
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  ref <- artifact_save(store, "kept", charToRaw("kept"), "text/plain")
  writeLines("unknown", file.path(store@path, "unknown.txt"))
  expect_error(graft_manifest(store), class = "graft_artifact_error")
  unlink(file.path(store@path, "unknown.txt"))

  payload <- artifact_read(store, ref)$metadata$payload
  writeBin(charToRaw("changed"), file.path(store@path, "content", payload))
  expect_error(graft_manifest(store), class = "graft_artifact_error")
})

test_that("manifest bounds are checked before payload reads", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  artifact_save(store, "kept", charToRaw("kept"), "text/plain")
  expect_error(
    graft_manifest(store, max_objects = 0),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_manifest(store, max_objects = 1),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_manifest(store, max_total_bytes = 1),
    class = "graft_artifact_error"
  )
})

test_that("empty stores have a stable empty manifest", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  dir.create(file.path(store@path, "content"))
  dir.create(file.path(store@path, "revisions"))
  dir.create(file.path(store@path, "selections"))
  dir.create(file.path(store@path, "decisions"))
  manifest <- graft_manifest(store)

  expect_identical(manifest$objects, list())
  expect_match(manifest$id, "^[0-9a-f]{64}$")
  expect_identical(graft_manifest(store), manifest)
})

test_that("incomplete decision directories are rejected", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  stream <- file.path(store@path, "decisions", strrep("a", 64))
  dir.create(stream, recursive = TRUE)
  expect_error(
    graft_manifest(store),
    class = "graft_artifact_error"
  )
})

test_that("staging and dangling links are rejected before reads", {
  skip_on_os("windows")
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  stream <- file.path(store@path, "decisions", strrep("a", 64))
  dir.create(stream, recursive = TRUE)
  writeBin(charToRaw("partial"), file.path(stream, "staged-interrupted"))
  expect_error(
    graft_manifest(store),
    class = "graft_artifact_error"
  )

  unlink(file.path(store@path, "decisions"), recursive = TRUE)
  content <- file.path(store@path, "content")
  dir.create(content)
  linked <- file.path(content, strrep("b", 64))
  expect_identical(file.symlink("missing-content", linked), TRUE)
  expect_error(
    graft_manifest(store),
    class = "graft_artifact_error"
  )
})

test_that("a nonregular marker is rejected without opening it", {
  skip_on_os("windows")
  skip_if(!nzchar(Sys.which("mkfifo")))
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  marker <- file.path(store@path, "store.json")
  unlink(marker)
  expect_identical(system2("mkfifo", shQuote(marker)), 0L)
  expect_error(
    graft_manifest(store),
    class = "graft_artifact_error"
  )
})

test_that("missing revision dependencies reject the complete inventory", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  source <- artifact_save(
    store,
    "source",
    charToRaw("source"),
    "text/plain"
  )
  artifact_save(
    store,
    "report",
    charToRaw("report"),
    "text/plain",
    dependencies = list(source)
  )
  unlink(file.path(store@path, "revisions", source$revision))
  expect_error(
    graft_manifest(store),
    class = "graft_artifact_error"
  )
})

test_that("decision history cannot certify without every historical selection", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  ref <- artifact_save(store, "report", charToRaw("report"), "text/plain")
  selection <- artifact_select(store, list(ref))
  artifact_decide(
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
  corrected <- artifact_save(
    store,
    "report",
    charToRaw("corrected"),
    "text/plain"
  )
  current <- artifact_select(store, list(corrected))
  artifact_decide(
    store,
    "subject",
    "correction",
    expected = artifact_read_decision(store, "subject")$id,
    selection = current,
    action = "accept",
    actor = "reviewer",
    reason = "corrected",
    purpose = "research"
  )
  unlink(file.path(store@path, "selections", selection))
  expect_identical(artifact_read_selection(store, current)$id, current)
  expect_error(
    graft_manifest(store),
    class = "graft_artifact_error"
  )
})

test_that("dangling links in fixed kind paths cannot hide an object set", {
  skip_on_os("windows")
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  expect_identical(
    file.symlink("missing-directory", file.path(store@path, "content")),
    TRUE
  )
  expect_error(graft_manifest(store), class = "graft_artifact_error")
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

test_that("the lock directory is not part of a store's manifest", {
  f <- local_decision_fixture()
  decision_submit(f$request)
  expect_setequal(
    list.files(file.path(f$store@path, "locks")),
    c("store.lock", paste0(artifact_sha(charToRaw("topic")), ".lock"))
  )
  kinds <- vapply(graft_manifest(f$store)$objects, \(x) x$kind, character(1))
  expect_identical(intersect(kinds, "locks"), character())
  expect_contains(kinds, "decisions")
})

test_that("the lock directory holds only stream lock files", {
  f <- local_decision_fixture()
  decision_submit(f$request)
  locks <- file.path(f$store@path, "locks")

  writeLines("stray", file.path(locks, "notes.txt"))
  expect_error(graft_manifest(f$store), class = "graft_artifact_error")
  unlink(file.path(locks, "notes.txt"))

  nested <- file.path(locks, paste0(strrep("c", 64), ".lock"))
  dir.create(nested)
  expect_error(graft_manifest(f$store), class = "graft_artifact_error")
  unlink(nested, recursive = TRUE)

  expect_no_error(graft_manifest(f$store))
})

test_that("a linked lock file cannot pass as a stream lock", {
  skip_on_os("windows")
  f <- local_decision_fixture()
  decision_submit(f$request)
  linked <- file.path(f$store@path, "locks", paste0(strrep("d", 64), ".lock"))
  expect_identical(file.symlink("missing-lock", linked), TRUE)
  expect_error(graft_manifest(f$store), class = "graft_artifact_error")
})
