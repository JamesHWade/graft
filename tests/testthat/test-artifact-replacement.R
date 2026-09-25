test_that("replacement plans remove reverse dependents and affected streams", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  fixture <- artifact_recovery_fixture(source)
  orphan <- charToRaw("orphan bytes")
  orphan_digest <- digest::digest(orphan, algo = "sha256", serialize = FALSE)
  dir.create(file.path(source@path, "content"), showWarnings = FALSE)
  writeBin(orphan, file.path(source@path, "content", orphan_digest))

  plan <- graft_plan_replacement(
    source,
    forget = list(fixture$leaf, fixture$forgotten),
    forget_streams = c("explicit-stream")
  )

  expect_identical(
    artifact_recovery_ref_keys(plan$forget),
    artifact_recovery_ref_keys(list(fixture$leaf, fixture$forgotten))
  )
  expect_setequal(
    artifact_recovery_removed_ref_keys(plan),
    artifact_recovery_ref_keys(
      list(fixture$leaf, fixture$dependent, fixture$forgotten)
    )
  )
  expect_setequal(
    plan$removed$selections,
    fixture$removed_selection
  )
  expect_setequal(
    plan$removed$streams,
    c("removed-stream", "mixed-stream", "explicit-stream")
  )

  target_objects <- artifact_recovery_manifest_keys(plan$target)
  shared_digest <- digest::digest(
    charToRaw("shared bytes"),
    algo = "sha256",
    serialize = FALSE
  )
  expect_identical(
    any(grepl(
      paste0("^content\\n", shared_digest, "$"),
      target_objects
    )),
    TRUE
  )
  expect_identical(
    any(grepl(
      paste0("^content\\n", orphan_digest, "$"),
      target_objects
    )),
    FALSE
  )
})

test_that("stream-only plans and literal stream names retain independent revisions", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  old <- artifact_save(
    source,
    "same-id",
    charToRaw("old"),
    "text/plain"
  )
  current <- artifact_save(
    source,
    "same-id",
    charToRaw("current"),
    "text/plain"
  )
  old_selection <- artifact_select(source, list(old))
  current_selection <- artifact_select(source, list(current))
  old_decision <- artifact_decide(
    source,
    "records",
    "old",
    NULL,
    old_selection,
    "accept",
    "reviewer",
    "old",
    "research"
  )
  current_decision <- artifact_decide(
    source,
    "names",
    "current",
    NULL,
    current_selection,
    "accept",
    "reviewer",
    "current",
    "research"
  )

  stream_only <- graft_plan_replacement(
    source,
    forget = list(),
    forget_streams = "records"
  )
  expect_identical(stream_only$forget, list())
  expect_identical(stream_only$forget_streams, "records")
  expect_identical(stream_only$removed$streams, "records")

  plan <- graft_plan_replacement(
    source,
    forget = list(old),
    forget_streams = "records"
  )
  expect_identical(
    artifact_recovery_removed_ref_keys(plan),
    artifact_recovery_ref_keys(list(old))
  )
  expect_identical(plan$removed$streams, "records")
  expect_identical(
    plan$target$objects[
      vapply(plan$target$objects, \(x) x$kind == "revisions", logical(1))
    ][[1L]]$key,
    current$revision
  )

  target <- graft_store(withr::local_tempdir(), create = TRUE)
  graft_replace(source, target, plan)
  expect_identical(
    artifact_read(target, current)$bytes,
    charToRaw("current")
  )
  expect_identical(
    artifact_read_decision(target, "names"),
    current_decision
  )
  expect_null(artifact_read_decision(target, "records"))
  expect_identical(old_decision$stream, "records")
})

test_that("replacement inputs require existing roots or streams within bounds", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  fixture <- artifact_recovery_fixture(source)

  expect_error(
    graft_plan_replacement(
      source,
      forget = list(),
      forget_streams = "missing-stream"
    ),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_plan_replacement(
      source,
      forget = list(fixture$leaf),
      max_objects = 1
    ),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_plan_replacement(
      source,
      forget = list(fixture$leaf),
      max_total_bytes = 1
    ),
    class = "graft_artifact_error"
  )
})

test_that("replacement rejects tampered plans, stale sources and nonempty targets", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  fixture <- artifact_recovery_fixture(source)
  plan <- artifact_recovery_plan(source, fixture)
  before <- graft_manifest(source)

  tampered <- plan
  tampered$removed$streams <- "retained-stream"
  target <- graft_store(withr::local_tempdir(), create = TRUE)
  empty_before <- graft_manifest(target)
  expect_error(
    graft_replace(source, target, tampered),
    class = "graft_artifact_error"
  )
  expect_identical(graft_manifest(target), empty_before)
  expect_identical(graft_manifest(source), before)

  artifact_save(source, "later", charToRaw("later"), "text/plain")
  stale_before <- graft_manifest(source)
  fresh_target <- graft_store(withr::local_tempdir(), create = TRUE)
  expect_error(
    graft_replace(source, fresh_target, plan),
    class = "graft_artifact_error"
  )
  expect_identical(graft_manifest(fresh_target), empty_before)

  nonempty_target <- graft_store(withr::local_tempdir(), create = TRUE)
  artifact_save(
    nonempty_target,
    "existing",
    charToRaw("existing"),
    "text/plain"
  )
  current_plan <- artifact_recovery_plan(source, fixture)
  nonempty_before <- graft_manifest(nonempty_target)
  expect_error(
    graft_replace(source, nonempty_target, current_plan),
    class = "graft_artifact_error"
  )
  expect_identical(graft_manifest(nonempty_target), nonempty_before)
  expect_identical(graft_manifest(source), stale_before)
})

test_that("replacement copy failures leave the source unchanged", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  fixture <- artifact_recovery_fixture(source)
  plan <- artifact_recovery_plan(source, fixture)
  before <- graft_manifest(source)
  target <- graft_store(withr::local_tempdir(), create = TRUE)

  local_mocked_bindings(artifact_storage_put = function(...) {
    artifact_abort("Injected replacement copy failure.")
  })
  expect_error(
    graft_replace(source, target, plan),
    class = "graft_artifact_error"
  )
  expect_identical(graft_manifest(source), before)
})

test_that("replacement rechecks the source after a copy mutation", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  fixture <- artifact_recovery_fixture(source)
  plan <- artifact_recovery_plan(source, fixture)
  target <- graft_store(withr::local_tempdir(), create = TRUE)
  original <- artifact_storage_put
  mutated <- FALSE
  local_mocked_bindings(artifact_storage_put = function(
    store,
    kind,
    key,
    bytes,
    limit
  ) {
    result <- original(store, kind, key, bytes, limit)
    if (identical(store@path, target@path) && !mutated) {
      mutated <<- TRUE
      artifact_save(
        source,
        "concurrent",
        charToRaw("changed"),
        "text/plain"
      )
    }
    result
  })
  expect_error(
    graft_replace(source, target, plan),
    class = "graft_artifact_error"
  )
  expect_identical(mutated, TRUE)
})

test_that("selection and journal copies use the replacement metadata bound", {
  source <- graft_store(
    withr::local_tempdir(),
    create = TRUE,
    max_revision_bytes = 512
  )
  roots <- lapply(seq_len(8L), function(index) {
    artifact_save(
      source,
      paste0("root-", index),
      charToRaw(paste0("root ", index)),
      "text/plain"
    )
  })
  forgotten <- artifact_save(
    source,
    "forgotten",
    charToRaw("forgotten"),
    "text/plain"
  )
  selection <- artifact_select(
    source,
    roots,
    max_metadata_bytes = 64 * 1024
  )
  decision <- artifact_decide(
    source,
    "retained",
    "review",
    NULL,
    selection,
    "accept",
    "reviewer",
    paste0(strrep("reason", 100L), "x"),
    "research",
    max_metadata_bytes = 64 * 1024
  )
  plan <- graft_plan_replacement(
    source,
    forget = list(forgotten),
    max_metadata_bytes = 64 * 1024
  )
  target <- graft_store(
    withr::local_tempdir(),
    create = TRUE,
    max_revision_bytes = 512
  )
  expect_identical(graft_replace(source, target, plan), plan$target)
  expect_identical(
    artifact_read_selection(
      target,
      selection,
      max_metadata_bytes = 64 * 1024
    )$id,
    selection
  )
  expect_identical(
    artifact_read_decision(
      target,
      "retained",
      max_metadata_bytes = 64 * 1024
    ),
    decision
  )
})

test_that("replacement preflight rejects FIFO markers before store reads", {
  skip_on_os("windows")
  skip_if(!nzchar(Sys.which("mkfifo")))

  source <- graft_store(withr::local_tempdir(), create = TRUE)
  root <- artifact_save(
    source,
    "fifo-plan",
    charToRaw("fifo-plan"),
    "text/plain"
  )
  marker <- file.path(source@path, "store.json")
  unlink(marker)
  expect_identical(system2("mkfifo", shQuote(marker)), 0L)
  expect_error(
    graft_plan_replacement(source, list(root)),
    class = "graft_artifact_error"
  )

  source <- graft_store(withr::local_tempdir(), create = TRUE)
  root <- artifact_save(
    source,
    "fifo-replace",
    charToRaw("fifo-replace"),
    "text/plain"
  )
  plan <- graft_plan_replacement(source, list(root))
  target <- graft_store(withr::local_tempdir(), create = TRUE)
  marker <- file.path(target@path, "store.json")
  unlink(marker)
  expect_identical(system2("mkfifo", shQuote(marker)), 0L)
  expect_error(
    graft_replace(source, target, plan),
    class = "graft_artifact_error"
  )
})

test_that("a plan with nothing to forget leaves out only unreferenced content", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  fixture <- artifact_recovery_fixture(source)
  orphan <- charToRaw("orphan bytes")
  orphan_digest <- digest::digest(orphan, algo = "sha256", serialize = FALSE)
  writeBin(orphan, file.path(source@path, "content", orphan_digest))

  plan <- graft_plan_replacement(source)
  expect_identical(plan$forget, list())
  expect_identical(plan$removed$artifacts, list())
  expect_identical(plan$removed$selections, character())
  expect_identical(plan$removed$streams, character())

  source_keys <- artifact_recovery_manifest_keys(graft_manifest(source))
  target_keys <- artifact_recovery_manifest_keys(plan$target)
  expect_identical(
    setdiff(source_keys, target_keys),
    paste0("content\n", orphan_digest)
  )

  target <- graft_store(withr::local_tempdir(), create = TRUE)
  expect_identical(graft_replace(source, target, plan), plan$target)
  expect_identical(
    artifact_read(target, fixture$leaf)$bytes,
    artifact_read(source, fixture$leaf)$bytes
  )
})
