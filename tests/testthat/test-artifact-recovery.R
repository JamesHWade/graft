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

test_that("local inventory stops at the first exceeded bound", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  for (text in c("one", "two", "three")) {
    artifact_save(store, text, charToRaw(text), "text/plain")
  }
  sized <- 0L
  local_mocked_bindings(artifact_recovery_file_size = function(path) {
    sized <<- sized + 1L
    file.info(path)$size
  })

  expect_error(
    graft_manifest(store, max_objects = 2),
    "object-count bound",
    class = "graft_artifact_error"
  )
  expect_identical(sized, 0L)

  expect_error(
    graft_manifest(store, max_total_bytes = 4),
    "total byte bound",
    class = "graft_artifact_error"
  )
  expect_identical(sized, 2L)
})

test_that("local inventory counts decision streams before reading them", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  ref <- artifact_save(store, "kept", charToRaw("kept"), "text/plain")
  selection <- artifact_select(store, list(ref))
  for (stream in c("a", "b", "c")) {
    artifact_decide(
      store,
      stream,
      "review",
      expected = NULL,
      selection = selection,
      action = "accept",
      actor = "reviewer",
      reason = "reviewed",
      purpose = "research"
    )
  }
  expect_no_error(graft_manifest(store, max_objects = 6))
  local_mocked_bindings(artifact_recovery_directory = function(path) {
    if (grepl("decisions/[0-9a-f]{64}$", path)) {
      stop("stream directory examined")
    }
    isTRUE(file.info(path)$isdir)
  })
  expect_error(
    graft_manifest(store, max_objects = 5),
    "object-count bound",
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

test_that("recovery ignores empty decision directories without records", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  stream_name <- "empty-journal"
  stream <- file.path(
    store@path,
    "decisions",
    artifact_sha(charToRaw(stream_name))
  )
  dir.create(stream, recursive = TRUE)
  expect_error(
    artifact_recovery_snapshot(store),
    class = "graft_artifact_error"
  )

  expect_identical(graft_manifest(store)$objects, list())
  expect_identical(graft_manifest(store)$objects, list())
  expect_length(graft_history(store, stream_name), 0L)
  expect_length(graft_streams(store), 0L)
  expect_identical(dir.exists(stream), TRUE)
})

test_that("manifest removes recognized abandoned staging files", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  content <- file.path(store@path, "content")
  dir.create(content)
  staged_content <- tempfile("staged-", tmpdir = content)
  writeBin(charToRaw("partial"), staged_content)

  content_manifest <- graft_manifest(store)

  expect_identical(content_manifest$objects, list())
  expect_identical(file.exists(staged_content), FALSE)

  stream <- file.path(store@path, "decisions", strrep("a", 64))
  dir.create(stream, recursive = TRUE)
  staged_decision <- tempfile("staged-", tmpdir = stream)
  writeBin(charToRaw("partial"), staged_decision)

  decision_manifest <- graft_manifest(store)

  expect_identical(decision_manifest$objects, list())
  expect_identical(file.exists(staged_decision), FALSE)
  expect_identical(dir.exists(stream), TRUE)
})

test_that("malformed staging and unknown paths remain fail-closed", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  content <- file.path(store@path, "content")
  dir.create(content)
  malformed <- file.path(content, "staged-not-hex")
  writeBin(charToRaw("unknown"), malformed)
  expect_error(
    graft_manifest(store),
    class = "graft_artifact_error"
  )
  expect_identical(file.exists(malformed), TRUE)

  unlink(malformed)
  staged <- tempfile("staged-", tmpdir = content)
  writeBin(charToRaw("partial"), staged)
  unknown <- file.path(store@path, "unknown.txt")
  writeLines("unknown", unknown)
  expect_error(graft_manifest(store), class = "graft_artifact_error")
  expect_identical(file.exists(staged), TRUE)
  expect_identical(file.exists(unknown), TRUE)

  unlink(unknown)
  expect_no_error(graft_manifest(store))
  expect_identical(file.exists(staged), FALSE)
})

test_that("staging and dangling links remain fail-closed", {
  skip_on_os("windows")
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  content <- file.path(store@path, "content")
  dir.create(content)
  linked_staging <- tempfile("staged-", tmpdir = content)
  expect_identical(file.symlink("missing-staging", linked_staging), TRUE)
  expect_error(graft_manifest(store), class = "graft_artifact_error")
  expect_identical(Sys.readlink(linked_staging), "missing-staging")

  unlink(content, recursive = TRUE)
  content <- file.path(store@path, "content")
  dir.create(content)
  linked <- file.path(content, strrep("b", 64))
  expect_identical(file.symlink("missing-content", linked), TRUE)
  expect_error(
    graft_manifest(store),
    class = "graft_artifact_error"
  )
})

test_that("staging cleanup observes object and byte bounds before removal", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  content <- file.path(store@path, "content")
  dir.create(content)
  staged <- vapply(
    seq_len(2),
    function(i) {
      path <- tempfile("staged-", tmpdir = content)
      writeBin(charToRaw(paste0("partial-", i)), path)
      path
    },
    character(1)
  )

  expect_error(
    graft_manifest(store, max_objects = 1),
    "object-count bound",
    class = "graft_artifact_error"
  )
  expect_identical(file.exists(staged), c(TRUE, TRUE))

  expect_error(
    graft_manifest(store, max_total_bytes = 1),
    "abandoned-staging byte bound",
    class = "graft_artifact_error"
  )
  expect_identical(file.exists(staged), c(TRUE, TRUE))
})

test_that("staging remains when a revision exceeds its byte bound", {
  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)
  ref <- artifact_save(
    store,
    "revision bound",
    charToRaw("revision bytes"),
    "text/plain"
  )
  revision_size <- file.info(
    file.path(path, "revisions", ref$revision)
  )$size
  small_store <- graft_store(
    path,
    max_revision_bytes = revision_size - 1
  )
  staged <- file.path(path, "content", "staged-a")
  writeBin(charToRaw("partial"), staged)

  expect_error(
    graft_manifest(small_store),
    "revision byte bound",
    class = "graft_artifact_error"
  )
  expect_identical(file.exists(staged), TRUE)
})

test_that("staging remains when a decision stream exceeds its metadata bound", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  ref <- graft_save(store, "report", "decision bound")
  first <- graft_accept(
    store,
    ref,
    "metadata-bound",
    expected = NULL,
    key = "first",
    actor = "reviewer",
    reason = "first",
    purpose = "test"
  )
  graft_accept(
    store,
    ref,
    "metadata-bound",
    expected = first,
    key = "second",
    actor = "reviewer",
    reason = "second",
    purpose = "test"
  )
  stream <- file.path(
    store@path,
    "decisions",
    artifact_sha(charToRaw("metadata-bound"))
  )
  records <- list.files(stream, full.names = TRUE)
  sizes <- file.info(records)$size
  bound <- max(sizes)
  expect_gt(sum(sizes), bound)
  staged <- file.path(stream, "staged-a")
  writeBin(charToRaw("partial"), staged)

  expect_error(
    graft_manifest(store, max_metadata_bytes = bound),
    "metadata bound",
    class = "graft_artifact_error"
  )
  expect_identical(file.exists(staged), TRUE)
})

test_that("a read-only manifest leaves staging untouched and fails closed", {
  skip_on_os("windows")
  skip_if(identical(Sys.info()[["user"]], "root"))
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  content <- file.path(store@path, "content")
  dir.create(content)
  staged <- tempfile("staged-", tmpdir = content)
  writeBin(charToRaw("partial"), staged)
  withr::defer(Sys.chmod(store@path, "0755"))
  Sys.chmod(store@path, "0555")

  expect_error(graft_manifest(store), class = "graft_artifact_error")
  expect_identical(file.exists(staged), TRUE)
})

test_that("a manifest waits for a live writer before cleaning staging", {
  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE, lock_timeout = 0.2)
  ready <- tempfile()
  checkout <- if (pkgload::is_dev_package("graft")) {
    normalizePath(test_path("../.."))
  } else {
    NULL
  }
  writer <- callr::r_bg(
    function(path, checkout, ready) {
      if (!is.null(checkout)) {
        pkgload::load_all(checkout, quiet = TRUE)
      }
      store <- graft::graft_store(path, lock_timeout = 0.2)
      graft::graft_with_store_lock(
        store,
        {
          content <- file.path(store@path, "content")
          dir.create(content, showWarnings = FALSE)
          staged <- tempfile("staged-", tmpdir = content)
          writeBin(charToRaw("live write"), staged)
          writeLines(staged, ready)
          Sys.sleep(30)
        },
        exclusive = FALSE
      )
    },
    args = list(path = path, checkout = checkout, ready = ready)
  )
  withr::defer(writer$kill())
  deadline <- Sys.time() + 10
  while (!file.exists(ready) && writer$is_alive() && Sys.time() < deadline) {
    Sys.sleep(0.01)
  }
  expect_identical(file.exists(ready), TRUE)
  staged <- readLines(ready, warn = FALSE)
  expect_identical(file.exists(staged), TRUE)

  expect_error(
    graft_manifest(store),
    class = "graft_store_busy_error"
  )
  expect_identical(file.exists(staged), TRUE)

  writer$kill()
  expect_no_error(graft_manifest(store))
  expect_identical(file.exists(staged), FALSE)
})

test_that("killed writers leave staging that a later inventory recovers", {
  skip_on_os("windows")
  checkout <- if (pkgload::is_dev_package("graft")) {
    normalizePath(test_path("../.."))
  } else {
    NULL
  }
  kill_writer <- function(path, mode) {
    callr::r_bg(
      function(path, checkout, mode) {
        if (!is.null(checkout)) {
          pkgload::load_all(checkout, quiet = TRUE)
        }
        store <- graft::graft_store(path, lock_timeout = 2)
        if (identical(mode, "content")) {
          trace(
            "artifact_rename_file",
            tracer = quote(tools::pskill(Sys.getpid(), tools::SIGKILL)),
            where = asNamespace("graft"),
            print = FALSE
          )
          graft::graft_save(
            store,
            "content interrupted",
            "recovery/content"
          )
        } else {
          trace(
            "artifact_rename_file",
            tracer = quote(
              if (
                grepl(
                  "/decisions/",
                  to,
                  fixed = TRUE
                )
              ) {
                tools::pskill(Sys.getpid(), tools::SIGKILL)
              }
            ),
            where = asNamespace("graft"),
            print = FALSE
          )
          ref <- graft::graft_save(
            store,
            "decision payload",
            "recovery/decision"
          )
          graft::graft_accept(
            store,
            ref,
            "recovery/stream",
            expected = NULL,
            key = "first",
            actor = "test",
            reason = "recovery",
            purpose = "test"
          )
        }
      },
      args = list(path = path, checkout = checkout, mode = mode)
    )
  }

  content_path <- withr::local_tempdir()
  content_store <- graft_store(content_path, create = TRUE)
  content_writer <- kill_writer(content_path, "content")
  withr::defer(content_writer$kill())
  content_writer$wait()
  expect_identical(content_writer$get_exit_status() == 0L, FALSE)
  content_staging <- list.files(
    file.path(content_path, "content"),
    pattern = "^staged-",
    full.names = TRUE
  )
  expect_length(content_staging, 1L)
  expect_length(graft_manifest(content_store)$objects, 0L)
  expect_identical(file.exists(content_staging), FALSE)
  content_ref <- graft_save(
    content_store,
    "content interrupted",
    "recovery/content"
  )
  expect_identical(
    graft_read(content_store, content_ref)@data,
    "content interrupted"
  )

  decision_path <- withr::local_tempdir()
  decision_store <- graft_store(decision_path, create = TRUE)
  decision_ref <- graft_save(
    decision_store,
    "decision payload",
    "recovery/decision"
  )
  decision_writer <- kill_writer(decision_path, "decision")
  withr::defer(decision_writer$kill())
  decision_writer$wait()
  expect_identical(decision_writer$get_exit_status() == 0L, FALSE)
  decision_staging <- list.files(
    file.path(decision_path, "decisions"),
    pattern = "^staged-",
    recursive = TRUE,
    full.names = TRUE
  )
  expect_length(decision_staging, 1L)
  decision_plan <- graft_plan_replacement(decision_store)
  expect_length(decision_plan$source$objects, 3L)
  expect_identical(file.exists(decision_staging), FALSE)
  expect_length(graft_manifest(decision_store)$objects, 3L)
  accepted <- graft_accept(
    decision_store,
    decision_ref,
    "recovery/stream",
    expected = NULL,
    key = "first",
    actor = "test",
    reason = "recovery",
    purpose = "test"
  )
  expect_identical(accepted@action, "accept")
  expect_length(graft_manifest(decision_store)$objects, 4L)
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
