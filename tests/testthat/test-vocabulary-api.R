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
    vocabulary_encode(value),
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
