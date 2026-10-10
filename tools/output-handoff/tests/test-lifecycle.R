test_that("reviewed Commons output survives a fresh session and withdrawal", {
  path <- tempfile("handoff-lifecycle-")
  withr::defer(unlink(path, recursive = TRUE))
  store <- graft::graft_store(path, create = TRUE)
  dictionary <- graft::graft_save(
    store,
    "count is an observed integer",
    "input:dictionary"
  )
  source <- graft::graft_save(
    store,
    '{"term":"Headache","count":6}',
    "input:observations",
    media_type = "application/json",
    dependencies = dictionary
  )
  inputs <- graft::graft_select(store, source)
  packet <- commons_completion(
    handoff_commons_value(),
    operation_id = "commons-lifecycle",
    producer = list(
      name = "synthetic_measure",
      version = "fixture-1",
      evidence = list(
        sql = "SELECT term, count FROM observations",
        raw_citations = list(
          "Synthetic fixture: Headache was observed 6 times."
        ),
        origin = "Explicit fixture producer metadata; not inferred from model text"
      )
    )
  )
  candidate <- retain_completed_output(
    store,
    packet,
    inputs,
    id = "analysis:commons",
    eligible = \() TRUE
  )
  expect_identical(
    graft::graft_recall(store, "analysis", "research", eligible = TRUE)@status,
    "missing"
  )
  acceptance <- graft::graft_accept(
    store,
    candidate$root,
    stream = "analysis",
    expected = NULL,
    key = "review-1",
    actor = "fixture-reviewer",
    reason = "Reviewed exact producer outputs and inputs",
    purpose = "research"
  )
  expected <- lapply(candidate$outputs, function(ref) {
    graft::graft_read(store, ref)@bytes
  })
  root <- list(id = candidate$root@id, revision = candidate$root@revision)
  fresh <- callr::r(
    function(graft_source, path, root) {
      pkgload::load_all(graft_source, quiet = TRUE)
      store <- graft::graft_store(path)
      recall <- graft::graft_recall(
        store,
        "analysis",
        "research",
        eligible = TRUE
      )
      manifest <- jsonlite::fromJSON(
        rawToChar(recall@roots[[1L]]@bytes),
        simplifyVector = FALSE
      )
      list(
        status = recall@status,
        decision = recall@decision@id,
        root = list(
          id = recall@roots[[1L]]@ref@id,
          revision = recall@roots[[1L]]@ref@revision
        ),
        outputs = lapply(manifest$outputs, function(output) {
          graft::graft_read(
            store,
            graft::ArtifactRef(
              id = output$ref$id,
              revision = output$ref$revision
            )
          )@bytes
        }),
        closure_size = length(recall@artifacts),
        producer_namespaces = intersect(
          c("commons", "deputy"),
          loadedNamespaces()
        )
      )
    },
    args = list(graft_source = graft_source, path = path, root = root)
  )
  expect_identical(fresh$status, "accepted")
  expect_identical(fresh$decision, acceptance@id)
  expect_identical(fresh$root, root)
  expect_identical(fresh$outputs, expected)
  expect_identical(fresh$closure_size, 7L)
  expect_identical(fresh$producer_namespaces, character())
  evidence <- jsonlite::fromJSON(
    rawToChar(graft::graft_read(store, candidate$evidence)@bytes),
    simplifyVector = FALSE
  )
  expect_identical(evidence$producer$evidence$sql, packet$producer$evidence$sql)
  expect_identical(evidence$producer$commons_tag, "A")
  expect_identical(evidence$input_selection_id, inputs@id)
  graft::graft_withdraw(
    store,
    stream = "analysis",
    expected = acceptance,
    key = "withdraw-1",
    actor = "fixture-reviewer",
    reason = "Current reuse withdrawn"
  )
  withdrawn <- callr::r(
    function(graft_source, path, root) {
      pkgload::load_all(graft_source, quiet = TRUE)
      store <- graft::graft_store(path)
      recall <- graft::graft_recall(
        store,
        "analysis",
        "research",
        eligible = TRUE
      )
      list(
        status = recall@status,
        artifacts = length(recall@artifacts),
        historical = graft::graft_read(
          store,
          graft::ArtifactRef(id = root$id, revision = root$revision)
        )@bytes
      )
    },
    args = list(graft_source = graft_source, path = path, root = root)
  )
  expect_identical(withdrawn$status, "withdrawn")
  expect_identical(withdrawn$artifacts, 0L)
  expect_identical(
    withdrawn$historical,
    graft::graft_read(store, candidate$root)@bytes
  )
  expect_error(
    graft::graft_recall(store, "analysis", "research", eligible = FALSE),
    class = "graft_ineligible_error"
  )
})
