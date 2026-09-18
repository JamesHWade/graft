test_that("artifacts survive correction and process restart", {
  path <- withr::local_tempdir()
  store <- graft_artifact_store(path, create = TRUE)
  bytes <- as.raw(c(0, 255, 10, 13, 1))
  ref <- graft_artifact_save(
    store,
    "report:daily",
    bytes,
    "application/octet-stream"
  )
  expect_identical(
    graft_artifact_save(
      store,
      "report:daily",
      bytes,
      "application/octet-stream"
    ),
    ref
  )
  corrected <- graft_artifact_save(
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
      graft::graft_artifact_read(graft::graft_artifact_store(path), ref)
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
    rawToChar(graft_artifact_read(store, corrected)$bytes),
    "corrected"
  )
  empty <- graft_artifact_save(
    store,
    "empty",
    raw(),
    "application/octet-stream"
  )
  expect_identical(graft_artifact_read(store, empty)$bytes, raw())
})

test_that("creation refuses unrelated contents and reopening requires a marker", {
  path <- withr::local_tempdir()
  writeLines("keep", file.path(path, "user.txt"))
  expect_error(
    graft_artifact_store(path, create = TRUE),
    class = "graft_artifact_error"
  )
  expect_identical(readLines(file.path(path, "user.txt")), "keep")
  expect_error(graft_artifact_store(path), class = "graft_artifact_error")
  fresh <- file.path(path, "fresh")
  store <- graft_artifact_store(fresh, create = TRUE)
  expect_identical(graft_artifact_store(fresh), store)
  expect_error(
    graft_artifact_store(fresh, create = TRUE),
    class = "graft_artifact_error"
  )
  writeLines("unknown", file.path(fresh, "store.json"))
  expect_error(graft_artifact_store(fresh), class = "graft_artifact_error")
})

test_that("invalid inputs fail before artifact publication", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
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
      graft_artifact_save(store, id, raw(), "text/plain"),
      class = "graft_artifact_error"
    )
  }
  expect_error(
    graft_artifact_save(store, "id", "text", "text/plain"),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_artifact_save(store, "id", raw(), ""),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_artifact_read(store, list(id = "id", revision = "../outside")),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_artifact_read(store, list(revision = strrep("a", 64))),
    class = "graft_artifact_error"
  )
  expect_identical(list.files(store$path), "store.json")
  for (limit in list(0, -1, NA, Inf, 1.5, "1")) {
    expect_error(
      graft_artifact_store(store$path, max_bytes = limit),
      class = "graft_artifact_error"
    )
  }
})

test_that("reads reject corrupt payloads, revisions and mismatched identities", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  ref <- graft_artifact_save(store, "id", charToRaw("original"), "text/plain")
  item <- graft_artifact_read(store, ref)
  wrong <- ref
  wrong$id <- "different"
  expect_error(
    graft_artifact_read(store, wrong),
    class = "graft_artifact_error"
  )
  content <- file.path(store$path, "content", item$metadata$payload)
  writeBin(charToRaw("modified"), content)
  expect_error(graft_artifact_read(store, ref), class = "graft_artifact_error")
  expect_error(
    graft_artifact_save(store, "id", charToRaw("original"), "text/plain"),
    class = "graft_artifact_error"
  )
  unlink(content)
  expect_error(graft_artifact_read(store, ref), class = "graft_artifact_error")
  writeBin(item$bytes, content)
  writeBin(charToRaw("{}"), file.path(store$path, "revisions", ref$revision))
  expect_error(graft_artifact_read(store, ref), class = "graft_artifact_error")
})

test_that("byte limits apply at saving and reopening", {
  store <- graft_artifact_store(
    withr::local_tempdir(),
    create = TRUE,
    max_bytes = 4
  )
  expect_error(
    graft_artifact_save(store, "id", charToRaw("large"), "text/plain"),
    class = "graft_artifact_error"
  )
  ref <- graft_artifact_save(store, "id", charToRaw("four"), "text/plain")
  expect_error(
    graft_artifact_read(graft_artifact_store(store$path, max_bytes = 3), ref),
    class = "graft_artifact_error"
  )
})

test_that("metadata publication failures retain bytes and permit exact retry", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  original <- graft_artifact_save(
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
    graft_artifact_save(store, "id", charToRaw("after"), "text/plain"),
    class = "graft_artifact_error"
  )
  expect_length(list.files(file.path(store$path, "revisions")), 1)
  expect_length(list.files(file.path(store$path, "content")), 2)
  expect_identical(
    rawToChar(graft_artifact_read(store, original)$bytes),
    "before"
  )
  local_mocked_bindings(artifact_rename_file = function(from, to) {
    file.rename(from, to)
  })
  corrected <- graft_artifact_save(
    store,
    "id",
    charToRaw("after"),
    "text/plain"
  )
  expect_identical(
    graft_artifact_save(store, "id", charToRaw("after"), "text/plain"),
    corrected
  )
  expect_length(list.files(file.path(store$path, "revisions")), 2)
  expect_length(list.files(file.path(store$path, "content")), 2)
})
