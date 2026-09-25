test_that("artifacts survive correction and process restart", {
  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)
  bytes <- as.raw(c(0, 255, 10, 13, 1))
  ref <- artifact_save(
    store,
    "report:daily",
    bytes,
    "application/octet-stream"
  )
  expect_identical(
    artifact_save(
      store,
      "report:daily",
      bytes,
      "application/octet-stream"
    ),
    ref
  )
  corrected <- artifact_save(
    store,
    "report:daily",
    charToRaw("corrected"),
    "text/plain"
  )
  expect_length(unique(c(corrected$revision, ref$revision)), 2)
  result <- callr::r(
    function(path, ref, checkout) {
      if (!is.null(checkout)) {
        pkgload::load_all(checkout, quiet = TRUE)
      }
      graft:::artifact_read(graft::graft_store(path), ref)
    },
    list(
      path = path,
      ref = ref,
      checkout = if (pkgload::is_dev_package("graft")) {
        normalizePath("../..")
      } else {
        NULL
      }
    )
  )
  expect_identical(result$bytes, bytes)
  expect_identical(result$ref, ref)
  expect_identical(result$metadata$id, "report:daily")
  expect_equal(result$metadata$size, length(bytes))
  expect_identical(
    result$metadata$payload,
    digest::digest(bytes, algo = "sha256", serialize = FALSE)
  )
  expect_identical(
    rawToChar(artifact_read(store, corrected)$bytes),
    "corrected"
  )
  empty <- artifact_save(
    store,
    "empty",
    raw(),
    "application/octet-stream"
  )
  expect_identical(artifact_read(store, empty)$bytes, raw())
})

test_that("filesystem paths are validated independently of artifact text", {
  for (path in list(NULL, NA_character_, "", c("a", "b"), 1)) {
    expect_error(graft_store(path), class = "graft_artifact_error")
  }
  root <- withr::local_tempdir()
  withr::local_dir(root)
  path <- " retained artifacts"
  store <- graft_store(path, create = TRUE)
  ref <- artifact_save(store, "report", charToRaw("kept"), "text/plain")
  expect_identical(artifact_read(store, ref)$bytes, charToRaw("kept"))
  expect_identical(graft_store(store@path), store)
})

test_that("short relative paths remain usable after long-path normalization", {
  skip_if_not(identical(Sys.info()[["sysname"]], "Linux"))
  root <- withr::local_tempdir()
  parent <- do.call(file.path, c(list(root), rep(list(strrep("d", 80)), 14)))
  dir.create(parent, recursive = TRUE)
  withr::local_dir(parent)
  store <- graft_store("artifacts", create = TRUE)
  expect_gt(nchar(store@path, type = "bytes"), 1024)
  ref <- artifact_save(store, "report", charToRaw("kept"), "text/plain")
  reopened <- graft_store(store@path)
  expect_identical(artifact_read(reopened, ref)$bytes, charToRaw("kept"))
  expect_identical(reopened, store)
})

test_that("creation refuses unrelated contents and reopening requires a marker", {
  path <- withr::local_tempdir()
  writeLines("keep", file.path(path, "user.txt"))
  expect_error(
    graft_store(path, create = TRUE),
    class = "graft_artifact_error"
  )
  expect_identical(readLines(file.path(path, "user.txt")), "keep")
  expect_error(graft_store(path), class = "graft_artifact_error")
  fresh <- file.path(path, "fresh")
  store <- graft_store(fresh, create = TRUE)
  expect_identical(graft_store(fresh), store)
  expect_error(
    graft_store(fresh, create = TRUE),
    class = "graft_artifact_error"
  )
  writeLines("unknown", file.path(fresh, "store.json"))
  expect_error(graft_store(fresh), class = "graft_artifact_error")
})

test_that("invalid inputs fail before artifact publication", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  for (id in list(
    NULL,
    NA_character_,
    "",
    " padded ",
    c("a", "b"),
    1,
    "a\nb"
  )) {
    expect_error(
      artifact_save(store, id, raw(), "text/plain"),
      class = "graft_artifact_error"
    )
  }
  expect_error(
    artifact_save(store, "id", "text", "text/plain"),
    class = "graft_artifact_error"
  )
  expect_error(
    artifact_save(store, "id", raw(), ""),
    class = "graft_artifact_error"
  )
  expect_error(
    artifact_read(store, list(id = "id", revision = "../outside")),
    class = "graft_artifact_error"
  )
  expect_error(
    artifact_read(store, list(revision = strrep("a", 64))),
    class = "graft_artifact_error"
  )
  expect_identical(list.files(store@path), "store.json")
  for (limit in list(0, -1, NA, Inf, 1.5, "1")) {
    expect_error(
      graft_store(store@path, max_bytes = limit),
      class = "graft_artifact_error"
    )
  }
})

test_that("reads reject corrupt payloads, revisions and mismatched identities", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  ref <- artifact_save(store, "id", charToRaw("original"), "text/plain")
  item <- artifact_read(store, ref)
  wrong <- ref
  wrong$id <- "different"
  expect_error(
    artifact_read(store, wrong),
    class = "graft_artifact_error"
  )
  content <- file.path(store@path, "content", item$metadata$payload)
  writeBin(charToRaw("modified"), content)
  expect_error(artifact_read(store, ref), class = "graft_artifact_error")
  expect_error(
    artifact_save(store, "id", charToRaw("original"), "text/plain"),
    class = "graft_artifact_error"
  )
  unlink(content)
  expect_error(artifact_read(store, ref), class = "graft_artifact_error")
  writeBin(item$bytes, content)
  writeBin(charToRaw("{}"), file.path(store@path, "revisions", ref$revision))
  expect_error(artifact_read(store, ref), class = "graft_artifact_error")
})

test_that("byte limits apply at saving and reopening", {
  store <- graft_store(
    withr::local_tempdir(),
    create = TRUE,
    max_bytes = 4
  )
  expect_error(
    artifact_save(store, "id", charToRaw("large"), "text/plain"),
    class = "graft_artifact_error"
  )
  ref <- artifact_save(store, "id", charToRaw("four"), "text/plain")
  expect_error(
    artifact_read(graft_store(store@path, max_bytes = 3), ref),
    class = "graft_artifact_error"
  )
})

test_that("metadata publication failures retain bytes and permit exact retry", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  original <- artifact_save(
    store,
    "id",
    charToRaw("before"),
    "text/plain"
  )
  local_mocked_bindings(artifact_rename_file = function(from, to) {
    if (basename(dirname(to)) == "revisions") {
      return(FALSE)
    }
    file.rename(from, to)
  })
  expect_error(
    artifact_save(store, "id", charToRaw("after"), "text/plain"),
    class = "graft_artifact_error"
  )
  expect_length(list.files(file.path(store@path, "revisions")), 1)
  expect_length(list.files(file.path(store@path, "content")), 2)
  expect_identical(
    rawToChar(artifact_read(store, original)$bytes),
    "before"
  )
  local_mocked_bindings(artifact_rename_file = function(from, to) {
    file.rename(from, to)
  })
  corrected <- artifact_save(
    store,
    "id",
    charToRaw("after"),
    "text/plain"
  )
  expect_identical(
    artifact_save(store, "id", charToRaw("after"), "text/plain"),
    corrected
  )
  expect_length(list.files(file.path(store@path, "revisions")), 2)
  expect_length(list.files(file.path(store@path, "content")), 2)
})


test_that("creation does not treat an unreadable directory as empty", {
  skip_on_os("windows")
  path <- withr::local_tempdir()
  writeLines("keep", file.path(path, "user.txt"))
  withr::defer(Sys.chmod(path, "0700"))
  Sys.chmod(path, "0300")
  skip_if(
    file.access(path, 4L) == 0L,
    "Process can read restricted directories"
  )
  expect_error(
    graft_store(path, create = TRUE),
    class = "graft_artifact_error"
  )
  expect_identical(file.exists(file.path(path, "store.json")), FALSE)
  Sys.chmod(path, "0700")
  expect_identical(readLines(file.path(path, "user.txt")), "keep")
})
test_that("text bounds use persisted UTF-8 bytes before publication", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  too_long <- iconv(strrep("\u00e9", 600), from = "UTF-8", to = "latin1")
  expect_equal(nchar(too_long, type = "bytes"), 600)
  expect_error(
    artifact_save(store, too_long, raw(), "text/plain"),
    class = "graft_artifact_error"
  )
  expect_error(
    artifact_save(store, "report", raw(), too_long),
    class = "graft_artifact_error"
  )
  expect_identical(list.files(store@path), "store.json")
  boundary <- iconv(strrep("\u00e9", 512), from = "UTF-8", to = "latin1")
  ref <- artifact_save(store, boundary, raw(), "text/plain")
  expect_identical(
    artifact_read(store, ref)$metadata$id,
    enc2utf8(boundary)
  )
})

test_that("revision metadata has a configurable handle bound", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  refs <- lapply(seq_len(600), function(i) {
    artifact_save(
      store,
      paste0(strrep('"', 1000), i),
      raw(),
      "text/plain"
    )
  })
  expect_error(
    artifact_save(store, "report", raw(), "text/plain", refs),
    class = "graft_artifact_error"
  )
  larger <- graft_store(store@path, max_revision_bytes = 2 * 1024^2)
  ref <- artifact_save(larger, "report", raw(), "text/plain", refs)
  expect_gt(
    file.info(file.path(store@path, "revisions", ref$revision))$size,
    1024^2
  )
  expect_error(artifact_read(store, ref), class = "graft_artifact_error")
  reopened <- graft_store(store@path, max_revision_bytes = 2 * 1024^2)
  expect_identical(
    artifact_read(reopened, ref)$metadata$dependencies,
    refs
  )
  selection <- artifact_select(
    reopened,
    list(ref),
    max_metadata_bytes = 2 * 1024^2
  )
  expect_identical(
    artifact_read_selection(
      reopened,
      selection,
      max_metadata_bytes = 2 * 1024^2
    )$artifacts,
    c(list(ref), refs)
  )
  for (limit in list(0, -1, 1.5, NA_real_, Inf, "large", numeric())) {
    expect_error(
      graft_store(store@path, max_revision_bytes = limit),
      class = "graft_artifact_error"
    )
  }
})

test_that("raw vector attributes do not affect artifact publication or retries", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  bytes <- as.raw(c(0, 255))
  for (attributed in list(
    setNames(bytes, c("first", "second")),
    structure(bytes, class = "example"),
    structure(bytes, dim = c(1L, 2L)),
    structure(bytes, label = "payload")
  )) {
    ref <- artifact_save(
      store,
      "raw",
      attributed,
      "application/octet-stream"
    )
    expect_identical(artifact_read(store, ref)$bytes, bytes)
    expect_identical(
      artifact_save(store, "raw", attributed, "application/octet-stream"),
      ref
    )
  }
  expect_identical(
    artifact_save(store, "raw", bytes, "application/octet-stream"),
    ref
  )
})

test_that("host Graft error handlers catch artifact failures", {
  error <- tryCatch(graft_store(""), graft_error = identity)
  expect_s3_class(error, "graft_artifact_error")
})


test_that("identity and reference attributes do not change persisted values", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  bytes <- charToRaw("kept")
  ref <- artifact_save(store, c(label = "report"), bytes, I("text/plain"))
  expect_identical(ref$id, "report")
  expect_identical(
    artifact_read(store, ref)$metadata$media_type,
    "text/plain"
  )
  expect_identical(
    artifact_save(store, "report", bytes, "text/plain"),
    ref
  )
  attributed <- structure(
    list(id = I("report"), revision = c(digest = ref$revision)),
    class = "example"
  )
  result <- artifact_read(store, attributed)
  expect_identical(result$ref, ref)
  expect_identical(result$bytes, bytes)
})

test_that("opening a store rejects a FIFO marker without blocking", {
  skip_on_os("windows")
  skip_if(!nzchar(Sys.which("mkfifo")), "mkfifo is unavailable")
  path <- withr::local_tempdir()
  graft_store(path, create = TRUE)
  marker <- file.path(path, "store.json")
  unlink(marker)
  expect_equal(system2("mkfifo", shQuote(marker)), 0)
  result <- callr::r(
    function(path, checkout) {
      if (!is.null(checkout)) {
        pkgload::load_all(checkout, quiet = TRUE)
      }
      tryCatch(
        graft::graft_store(path),
        graft_artifact_error = function(cnd) class(cnd)[[1L]]
      )
    },
    list(
      path = path,
      checkout = if (pkgload::is_dev_package("graft")) {
        normalizePath("../..")
      } else {
        NULL
      }
    ),
    timeout = 10
  )
  expect_identical(result, "graft_artifact_error")
})

test_that("two processes saving the same bytes into fresh stores both succeed", {
  root <- withr::local_tempdir()
  paths <- file.path(root, sprintf("store-%02d", seq_len(40)))
  for (path in paths) {
    graft_store(path, create = TRUE)
  }
  go <- file.path(root, "go")
  worker <- function(paths, go, checkout) {
    if (!is.null(checkout)) {
      pkgload::load_all(checkout, quiet = TRUE)
    }
    while (!file.exists(go)) {
      Sys.sleep(0.001)
    }
    vapply(
      paths,
      function(path) {
        tryCatch(
          {
            graft::graft_save(graft::graft_store(path), "same bytes", "note")
            ""
          },
          error = function(e) conditionMessage(e)
        )
      },
      character(1)
    )
  }
  args <- list(paths = paths, go = go, checkout = graft_checkout())
  workers <- lapply(1:2, function(i) callr::r_bg(worker, args))
  file.create(go)
  for (w in workers) {
    w$wait(60000)
  }
  failures <- unlist(lapply(workers, \(w) w$get_result()))
  expect_identical(unique(failures), "")
})

test_that("a rename that loses to an identical publication still succeeds", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  local_mocked_bindings(artifact_rename_file = function(from, to) {
    # Another writer published the same digest first.
    file.copy(from, to)
    FALSE
  })
  ref <- artifact_save(store, "note", charToRaw("same"), "text/plain")
  expect_identical(rawToChar(artifact_read(store, ref)$bytes), "same")
  expect_length(list.files(store@path, "^staged-", recursive = TRUE), 0)
})

test_that("a failed rename with no or different bytes at the destination fails", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  local_mocked_bindings(artifact_rename_file = function(from, to) FALSE)
  expect_error(
    artifact_save(store, "note", charToRaw("same"), "text/plain"),
    "no successful reference"
  )
  local_mocked_bindings(artifact_rename_file = function(from, to) {
    writeBin(charToRaw("other"), to)
    FALSE
  })
  expect_error(
    artifact_save(store, "note", charToRaw("same"), "text/plain"),
    class = "graft_artifact_error"
  )
  expect_length(list.files(store@path, "^staged-", recursive = TRUE), 0)
})

test_that("a directory another process created first is used, not an error", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  local_mocked_bindings(artifact_create_dir = function(path) {
    dir.create(path, recursive = TRUE)
    FALSE
  })
  ref <- artifact_save(store, "note", charToRaw("same"), "text/plain")
  expect_identical(rawToChar(artifact_read(store, ref)$bytes), "same")
})

test_that("a losing rename's warning does not escape, even under warn = 2", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  withr::local_options(warn = 2)
  local_mocked_bindings(artifact_rename_file = function(from, to) {
    file.copy(from, to)
    warning("cannot rename file, reason 'Access is denied'")
    FALSE
  })
  ref <- expect_no_warning(
    artifact_save(store, "note", charToRaw("same"), "text/plain")
  )
  expect_identical(rawToChar(artifact_read(store, ref)$bytes), "same")
  local_mocked_bindings(artifact_rename_file = function(from, to) {
    warning("disk full")
    FALSE
  })
  expect_error(
    artifact_save(store, "other", charToRaw("new"), "text/plain"),
    "no successful reference"
  )
})

test_that("verifying a publication retries while another process replaces it", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  original <- artifact_bytes
  failures <- 2L
  local_mocked_bindings(artifact_bytes = function(path, limit) {
    if (failures > 0L && grepl("[/\\\\]content[/\\\\]", path)) {
      failures <<- failures - 1L
      artifact_abort("Could not read artifact bytes.")
    }
    original(path, limit)
  })
  ref <- artifact_save(store, "note", charToRaw("same"), "text/plain")
  expect_identical(failures, 0L)
  expect_identical(rawToChar(artifact_read(store, ref)$bytes), "same")
})
