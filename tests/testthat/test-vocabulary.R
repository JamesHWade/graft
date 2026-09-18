test_that("vocabulary releases preserve exact sources, exports and context", {
  fixture <- local_vocabulary()
  selection <- graft_vocabulary_publish(fixture$store, fixture$path)
  released <- graft_vocabulary_read(fixture$store, selection)
  expect_identical(
    graft_vocabulary_publish(fixture$store, fixture$path),
    selection
  )
  expect_identical(released$bindings$release, "urn:example:bindings:v1")
  expect_length(released$dictionaries, 2L)
  expect_match(
    paste(released$context, collapse = "\n"),
    "negated: true",
    fixed = TRUE
  )
  expect_match(
    paste(released$context, collapse = "\n"),
    "do not authorize joins",
    fixed = TRUE
  )
  expect_identical(
    released$references$bindings$sha256,
    digest::digest(file = fixture$path, algo = "sha256")
  )
  revised <- local_vocabulary("v2")
  correction <- graft_vocabulary_publish(fixture$store, revised$path)
  expect_identical(identical(selection, correction), FALSE)
  expect_identical(graft_vocabulary_read(fixture$store, selection), released)
  # Source files and the upstream CLI are unnecessary for historical reads.
  unlink(list.files(
    dirname(fixture$path),
    pattern = "[.](json|yaml)$",
    full.names = TRUE
  ))
  withr::local_envvar(DATA_DICT = "/missing/data-dict")
  reopened <- graft_artifact_store(file.path(
    dirname(fixture$path),
    "artifacts"
  ))
  expect_identical(graft_vocabulary_read(reopened, selection), released)
  expect_identical(
    graft_vocabulary_read(reopened, correction)$bindings$release,
    "urn:example:bindings:v2"
  )
})

test_that("vocabulary publication rejects ambiguous and invalid bindings", {
  fixture <- local_vocabulary()
  original <- jsonlite::read_json(fixture$path)
  variants <- list(
    missing_field = function(x) {
      x$bindings[[1]]$field <- "absent"
      x
    },
    ambiguous = function(x) {
      y <- x$bindings[[1]]
      y$id <- "duplicate"
      x$bindings <- c(x$bindings, list(y))
      x
    },
    direction = function(x) {
      x$bindings[[4]]$from <- "sample_id"
      x
    },
    qualifiers = function(x) {
      x$bindings[[4]]$grain <- "different grain"
      x
    },
    digest = function(x) {
      x$dictionaries[[1]]$sha256 <- strrep("0", 64)
      x
    },
    traversal = function(x) {
      x$dictionaries[[1]]$path <- "../lab-a.yaml"
      x
    },
    duplicate_dictionary = function(x) {
      x$dictionaries <- c(x$dictionaries, x$dictionaries[1])
      x
    }
  )
  for (mutate in variants) {
    jsonlite::write_json(mutate(original), fixture$path, auto_unbox = TRUE)
    expect_error(
      graft_vocabulary_publish(fixture$store, fixture$path),
      class = "graft_vocabulary_error"
    )
  }
})

test_that("vocabulary reads verify the source and generated context closure", {
  fixture <- local_vocabulary()
  selection <- graft_vocabulary_publish(fixture$store, fixture$path)
  selected <- graft_artifact_read_selection(fixture$store, selection)
  root <- graft_artifact_read(fixture$store, selected$roots[[1]])
  value <- jsonlite::fromJSON(rawToChar(root$bytes), simplifyVector = FALSE)
  value$references$context <- graft_artifact_save(
    fixture$store,
    "wrong-context",
    charToRaw("misleading"),
    "text/markdown"
  )
  altered <- graft_artifact_save(
    fixture$store,
    "altered-release",
    vocabulary_encode(value),
    "application/json",
    vocabulary_dependencies(value$references)
  )
  altered <- graft_artifact_select(fixture$store, list(altered))
  expect_error(
    graft_vocabulary_read(fixture$store, altered),
    "context differs",
    class = "graft_vocabulary_error"
  )
})

test_that("plain R and Commons consume the same published release", {
  skip_if_not_installed("commons")
  fixture <- local_vocabulary()
  release <- graft_vocabulary_read(
    fixture$store,
    graft_vocabulary_publish(fixture$store, fixture$path)
  )
  bindings <- Filter(
    \(x) x$kind == "concept" && x$term == "urn:example:temperature",
    release$bindings$bindings
  )
  expect_identical(
    vapply(bindings, \(x) x$field, character(1)),
    c("temperature_c", "temperature_f")
  )
  expect_identical(
    vapply(bindings, \(x) x$scope, character(1)),
    c("lab-a", "lab-b")
  )
  context_path <- withr::local_tempfile(fileext = ".md")
  writeLines(release$context, context_path)
  expect_s3_class(
    commons::context_layer(files = context_path),
    "commons_context_layer"
  )
  source <- commons::data_source(
    readings = data.frame(
      reading_id = "r1",
      sample_id = "s1",
      temperature_c = 20
    ),
    dictionary = file.path(dirname(fixture$path), "lab-a.yaml")
  )
  expect_s3_class(source, "commons_data_source")
})

test_that("invalid dictionary sources fail through public upstream validation", {
  fixture <- local_vocabulary()
  path <- file.path(dirname(fixture$path), "lab-a.yaml")
  writeLines("not: [valid", path)
  companion <- jsonlite::read_json(fixture$path)
  companion$dictionaries[[1L]]$sha256 <- digest::digest(
    file = path,
    algo = "sha256"
  )
  jsonlite::write_json(companion, fixture$path, auto_unbox = TRUE)
  expect_error(
    graft_vocabulary_publish(fixture$store, fixture$path),
    "data-dict validation/export failed",
    class = "graft_vocabulary_error"
  )
})
