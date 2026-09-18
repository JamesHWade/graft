test_that("selections pin complete evidence and meaning across corrections and restart", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  vocabulary <- graft_artifact_save(
    store,
    "vocabulary",
    charToRaw("concepts"),
    "text/plain"
  )
  dictionary <- graft_artifact_save(
    store,
    "dictionary",
    charToRaw("schema"),
    "text/plain",
    list(vocabulary)
  )
  source <- graft_artifact_save(
    store,
    "source",
    charToRaw("observed"),
    "text/plain",
    list(dictionary)
  )
  report <- graft_artifact_save(
    store,
    "report",
    charToRaw("initial"),
    "text/plain",
    list(source, dictionary, source)
  )
  selection <- graft_artifact_select(store, list(report, report))
  expected <- list(report, source, dictionary, vocabulary)
  expect_identical(
    graft_artifact_read_selection(store, selection)$artifacts,
    expected
  )
  expect_identical(graft_artifact_select(store, list(report)), selection)
  expect_identical(
    graft_artifact_read(store, report)$metadata$dependencies,
    list(source, dictionary)
  )
  revised <- graft_artifact_save(
    store,
    "report",
    charToRaw("correction"),
    "text/plain",
    list(source)
  )
  expect_length(unique(c(report$revision, revised$revision)), 2)
  result <- callr::r(
    function(path, selection, checkout) {
      if (!is.null(checkout)) {
        pkgload::load_all(checkout, quiet = TRUE)
      }
      store <- graft::graft_artifact_store(path)
      basis <- graft::graft_artifact_read_selection(store, selection)
      list(
        basis = basis,
        text = lapply(basis$artifacts, function(ref) {
          rawToChar(graft::graft_artifact_read(store, ref)$bytes)
        })
      )
    },
    list(
      path = store$path,
      selection = selection,
      checkout = if (pkgload::is_dev_package("graft")) {
        normalizePath("../..")
      } else {
        NULL
      }
    )
  )
  expect_identical(result$basis$roots, list(report))
  expect_identical(result$basis$artifacts, expected)
  expect_identical(
    result$text,
    list("initial", "observed", "schema", "concepts")
  )
  expect_named(result$basis, c("id", "roots", "artifacts"))
})

test_that("invalid and absent dependencies fail before saving any content", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  absent <- list(id = "missing", revision = strrep("a", 64))
  for (dependencies in list(
    list(absent),
    list("latest"),
    "bad",
    list(list(id = "bad", revision = "../file"))
  )) {
    expect_error(
      graft_artifact_save(
        store,
        "report",
        charToRaw("unsaved"),
        "text/plain",
        dependencies
      ),
      class = "graft_artifact_error"
    )
  }
  expect_identical(list.files(store$path), "store.json")
  expect_error(
    graft_artifact_select(store, list()),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_artifact_select(store, list(absent)),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_artifact_read_selection(store, "../outside"),
    class = "graft_artifact_error"
  )
})

test_that("selection traversal enforces count and aggregate byte bounds", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  first <- graft_artifact_save(store, "first", charToRaw("1234"), "text/plain")
  second <- graft_artifact_save(
    store,
    "second",
    charToRaw("5678"),
    "text/plain",
    list(first)
  )
  third <- graft_artifact_save(
    store,
    "third",
    charToRaw("9"),
    "text/plain",
    list(second)
  )
  expect_error(
    graft_artifact_select(store, list(third), max_artifacts = 2),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_artifact_save(
      store,
      "fourth",
      raw(),
      "text/plain",
      list(third),
      max_artifacts = 2
    ),
    class = "graft_artifact_error"
  )
  selection <- graft_artifact_select(store, list(third), max_artifacts = 3)
  expect_error(
    graft_artifact_read_selection(store, selection, max_artifacts = 2),
    class = "graft_artifact_error"
  )
  small <- graft_artifact_store(store$path, max_bytes = 8)
  expect_error(
    graft_artifact_read_selection(small, selection),
    class = "graft_artifact_error"
  )
  expect_length(
    graft_artifact_read_selection(
      graft_artifact_store(store$path, max_bytes = 9),
      selection
    )$artifacts,
    3
  )
  expect_error(
    graft_artifact_select(store, list(first, second), max_artifacts = 1),
    class = "graft_artifact_error"
  )
})

test_that("selection metadata has an independent configurable byte bound", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  roots <- lapply(seq_len(500), function(i) {
    graft_artifact_save(
      store,
      paste0(strrep('"', 1000), i),
      raw(),
      "text/plain"
    )
  })
  expect_error(
    graft_artifact_select(store, roots),
    class = "graft_artifact_error"
  )
  expect_length(list.files(file.path(store$path, "selections")), 0L)
  selection <- graft_artifact_select(
    store,
    roots,
    max_metadata_bytes = 4 * 1024^2
  )
  expect_gt(
    file.info(file.path(store$path, "selections", selection))$size,
    1024^2
  )
  expect_error(
    graft_artifact_read_selection(store, selection),
    class = "graft_artifact_error"
  )
  result <- graft_artifact_read_selection(
    graft_artifact_store(store$path),
    selection,
    max_metadata_bytes = 4 * 1024^2
  )
  expect_identical(result$roots, roots)
  expect_identical(result$artifacts, roots)
  for (limit in list(0, -1, 1.5, NA_real_, Inf, "large", numeric())) {
    expect_error(
      graft_artifact_select(store, roots, max_metadata_bytes = limit),
      class = "graft_artifact_error"
    )
    expect_error(
      graft_artifact_read_selection(
        store,
        selection,
        max_metadata_bytes = limit
      ),
      class = "graft_artifact_error"
    )
  }
})

test_that("reads independently reject incomplete selections even with valid digests", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  source <- graft_artifact_save(
    store,
    "source",
    charToRaw("source"),
    "text/plain"
  )
  report <- graft_artifact_save(
    store,
    "report",
    charToRaw("report"),
    "text/plain",
    list(source)
  )
  selection <- graft_artifact_select(store, list(report))
  forged <- charToRaw(as.character(jsonlite::toJSON(
    list(format = 1L, roots = list(report), artifacts = list(report)),
    auto_unbox = TRUE,
    null = "null",
    digits = NA
  )))
  digest <- digest::digest(forged, algo = "sha256", serialize = FALSE)
  writeBin(forged, file.path(store$path, "selections", digest))
  expect_error(
    graft_artifact_read_selection(store, digest),
    class = "graft_artifact_error"
  )
  source_item <- graft_artifact_read(store, source)
  writeBin(
    charToRaw("broken"),
    file.path(store$path, "content", source_item$metadata$payload)
  )
  expect_error(
    graft_artifact_read_selection(store, selection),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_artifact_save(store, "another", raw(), "text/plain", list(report)),
    class = "graft_artifact_error"
  )
})

test_that("selection publication failure has no successful record and can retry", {
  store <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  ref <- graft_artifact_save(
    store,
    "report",
    charToRaw("retained"),
    "text/plain"
  )
  local_mocked_bindings(artifact_rename_file = function(from, to) {
    if (basename(dirname(to)) == "selections") {
      return(FALSE)
    }
    file.rename(from, to)
  })
  expect_error(
    graft_artifact_select(store, list(ref)),
    class = "graft_artifact_error"
  )
  expect_length(list.files(file.path(store$path, "selections")), 0)
  expect_identical(rawToChar(graft_artifact_read(store, ref)$bytes), "retained")
  local_mocked_bindings(artifact_rename_file = function(from, to) {
    file.rename(from, to)
  })
  selection <- graft_artifact_select(store, list(ref))
  expect_identical(graft_artifact_select(store, list(ref)), selection)
  expect_identical(
    graft_artifact_read_selection(store, selection)$artifacts,
    list(ref)
  )
})
