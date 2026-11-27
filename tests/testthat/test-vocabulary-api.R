test_that("public vocabulary publication returns typed releases", {
  fixture <- local_vocabulary("v1")
  first <- graft_publish_vocabulary(fixture$store, fixture$path)

  expect_s7_class(first, VocabularyRelease)
  expect_s7_class(first@selection, ArtifactSelection)
  expect_identical(first@bindings$release, "urn:example:bindings:v1")
  expect_length(first@dictionaries, 2L)

  second_fixture <- local_vocabulary("v2")
  second <- graft_publish_vocabulary(fixture$store, second_fixture$path)
  expect_s7_class(second, VocabularyRelease)
  expect_identical(second@bindings$release, "urn:example:bindings:v2")
  expect_identical(
    identical(first@selection@id, second@selection@id),
    FALSE
  )
})

test_that("public vocabulary reads accept every selection form", {
  fixture <- local_vocabulary()
  release <- graft_publish_vocabulary(fixture$store, fixture$path)

  from_release <- graft_read_vocabulary(fixture$store, release)
  from_selection <- graft_read_vocabulary(fixture$store, release@selection)
  from_digest <- graft_read_vocabulary(fixture$store, release@selection@id)

  expect_identical(from_release, release)
  expect_identical(from_selection, release)
  expect_identical(from_digest, release)
})

test_that("public vocabulary reads reconstruct fields rather than cached fields", {
  fixture <- local_vocabulary()
  release <- graft_publish_vocabulary(fixture$store, fixture$path)
  cached <- release
  cached@vocabulary <- list(release = "tampered")
  cached@bindings <- list(release = "tampered")
  cached@dictionaries <- list()
  cached@references <- list()
  cached@context <- "tampered"

  reread <- graft_read_vocabulary(fixture$store, cached)

  expect_identical(reread@vocabulary, release@vocabulary)
  expect_identical(reread@bindings, release@bindings)
  expect_identical(reread@dictionaries, release@dictionaries)
  expect_identical(reread@references, release@references)
  expect_identical(reread@context, release@context)
})

test_that("public vocabulary reads work offline for an old release", {
  fixture <- local_vocabulary("v1")
  release <- graft_publish_vocabulary(fixture$store, fixture$path)
  revised <- local_vocabulary("v2")
  graft_publish_vocabulary(fixture$store, revised$path)

  unlink(list.files(
    dirname(fixture$path),
    pattern = "[.](json|yaml)$",
    full.names = TRUE
  ))
  withr::local_envvar(DATA_DICT = "/missing/data-dict")
  reopened <- graft_store(fixture$store@path)

  reread <- graft_read_vocabulary(reopened, release)
  expect_identical(reread, release)
})

test_that("public vocabulary reads reject a corrupted release closure", {
  fixture <- local_vocabulary()
  release <- graft_publish_vocabulary(fixture$store, fixture$path)
  selected <- artifact_read_selection(fixture$store, release@selection@id)
  root <- artifact_read(fixture$store, selected$roots[[1L]])
  value <- vocabulary_json(root$bytes)
  value$references$context <- artifact_save(
    fixture$store,
    "corrupt-context",
    charToRaw("corrupt"),
    "text/markdown"
  )
  altered <- artifact_save(
    fixture$store,
    "corrupt-release",
    artifact_encode(value),
    "application/json",
    vocabulary_dependencies(value$references)
  )
  altered <- artifact_select(fixture$store, list(altered))

  expect_error(
    graft_read_vocabulary(fixture$store, altered),
    "context differs",
    class = "graft_vocabulary_error"
  )
})

test_that("vocabulary publish, read, and validation work offline with mocked dictionary exports", {
  path <- withr::local_tempdir()
  source_dir <- system.file("examples", "vocabulary", "v1", package = "graft")
  file.copy(list.files(source_dir, full.names = TRUE), path)
  store <- graft_store(file.path(path, "artifacts"), create = TRUE)

  mock_export <- function(table_name, cols) {
    list(
      model = list(
        tables = list(list(
          name = table_name,
          columns = lapply(cols, \(col) list(name = col))
        ))
      ),
      evidence = list(command = "validate-spec", status = 0L),
      package_version = "0.1.0",
      binary_sha256 = strrep("a", 64L)
    )
  }
  local_mocked_bindings(vocabulary_read_dictionary = function(bytes) {
    text <- rawToChar(bytes)
    if (grepl("readings", text, fixed = TRUE)) {
      mock_export("readings", c("reading_id", "sample_id", "temperature_c"))
    } else {
      mock_export("assays", c("assay_id", "specimen", "temperature_f"))
    }
  })

  release <- graft_publish_vocabulary(store, file.path(path, "bindings.json"))
  expect_s7_class(release, VocabularyRelease)
  expect_match(
    capture.output(print(release)),
    "VocabularyRelease urn:example:bindings:v1"
  )

  selection_reads <- 0L
  real_read_selection <- artifact_read_selection
  local_mocked_bindings(artifact_read_selection = function(...) {
    selection_reads <<- selection_reads + 1L
    real_read_selection(...)
  })
  reread <- graft_read_vocabulary(store, release)
  expect_identical(reread, release)
  expect_identical(selection_reads, 1L)

  bad_bindings <- release@bindings
  bad_bindings$bindings[[4L]]$from <- "sample_id"
  expect_error(
    vocabulary_validate(bad_bindings, release@vocabulary, release@dictionaries),
    "direction/domain/range",
    class = "graft_vocabulary_error"
  )
})
