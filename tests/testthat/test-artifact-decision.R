test_that("decisions separate reviews, corrections, withdrawal and consultation", {
  f <- local_decision_fixture()
  expect_null(artifact_read_decision(f$store, "topic"))
  accepted <- decision_submit(f$request)
  expect_identical(accepted$sequence, 1L)
  expect_null(accepted$previous)
  expect_identical(decision_submit(f$request), accepted)
  current <- artifact_reuse(
    f$store,
    "topic",
    accepted$id,
    "research",
    TRUE
  )
  expect_identical(current$decision, accepted)
  expect_identical(current$selection$artifacts, list(f$first, f$source))

  reviewed <- decision_submit(
    f$request,
    key = "review-2",
    expected = accepted$id
  )
  expect_identical(reviewed$selection, accepted$selection)
  expect_identical(reviewed$previous, accepted$id)
  expect_length(unique(c(accepted$id, reviewed$id)), 2L)
  corrected <- decision_submit(
    f$request,
    key = "correction",
    expected = reviewed$id,
    selection = f$correction
  )
  expect_identical(corrected$previous, reviewed$id)
  expect_identical(corrected$selection, f$correction)
  expect_identical(
    artifact_read_decision(f$store, "topic", accepted$id),
    accepted
  )
  expect_error(
    artifact_reuse(f$store, "topic", accepted$id, "research", TRUE),
    class = "graft_artifact_error"
  )
  withdrawn <- decision_submit(
    f$request,
    key = "withdraw",
    expected = corrected$id,
    selection = f$correction,
    action = "withdraw",
    reason = "Needs review"
  )
  expect_identical(withdrawn$action, "withdraw")
  expect_identical(decision_submit(f$request), accepted)
  expect_identical(artifact_read_decision(f$store, "topic"), withdrawn)
  expect_error(
    artifact_reuse(f$store, "topic", corrected$id, "research", TRUE),
    class = "graft_artifact_error"
  )
  expect_error(
    artifact_reuse(f$store, "topic", withdrawn$id, "research", TRUE),
    class = "graft_artifact_error"
  )
  reaccepted <- decision_submit(
    f$request,
    key = "fresh-review",
    expected = withdrawn$id
  )
  expect_identical(
    artifact_reuse(
      f$store,
      "topic",
      reaccepted$id,
      "research",
      TRUE
    )$decision,
    reaccepted
  )
})

test_that("changed retries and stale predecessors cannot publish decisions", {
  f <- local_decision_fixture()
  accepted <- decision_submit(f$request)
  before <- decision_journal_files(f$store)
  for (change in list(
    list(actor = "different"),
    list(reason = "Different review"),
    list(purpose = "other"),
    list(selection = f$correction),
    list(expected = accepted$id),
    list(action = "withdraw")
  )) {
    expect_error(
      do.call(decision_submit, c(list(request = f$request), change)),
      class = "graft_artifact_error"
    )
  }
  expect_error(
    decision_submit(f$request, key = "stale"),
    class = "graft_artifact_error"
  )
  expect_identical(decision_journal_files(f$store), before)
  expect_identical(artifact_read_decision(f$store, "topic"), accepted)
})

test_that("input normalization and stream isolation preserve decision identity", {
  f <- local_decision_fixture()
  attributed <- utils::modifyList(
    f$request,
    list(
      stream = c(name = "topic"),
      key = I("review-1"),
      actor = c(name = "reviewer"),
      reason = I("Evidence reviewed"),
      purpose = c(name = "research"),
      selection = I(f$selection)
    )
  )
  accepted <- decision_submit(attributed)
  expect_identical(decision_submit(f$request), accepted)
  expect_identical(
    artifact_read_decision(f$store, I("topic"), c(id = accepted$id)),
    accepted
  )
  other <- decision_submit(f$request, stream = "other")
  expect_length(unique(c(accepted$id, other$id)), 2L)
  expect_error(
    artifact_read_decision(f$store, "other", accepted$id),
    class = "graft_artifact_error"
  )
})

test_that("malformed decisions fail before publishing and eligibility is explicit", {
  f <- local_decision_fixture()
  for (field in c("stream", "key", "actor", "reason", "purpose", "action")) {
    for (bad in list(
      NULL,
      NA_character_,
      "",
      " padded ",
      "a\nb",
      strrep("x", 1025)
    )) {
      request <- f$request
      request[field] <- list(bad)
      expect_error(
        do.call(artifact_decide, request),
        class = "graft_artifact_error"
      )
    }
  }
  expect_error(
    decision_submit(f$request, action = "maybe"),
    class = "graft_artifact_error"
  )
  expect_error(
    decision_submit(f$request, action = "withdraw"),
    class = "graft_artifact_error"
  )
  expect_length(decision_journal_files(f$store), 0L)
  accepted <- decision_submit(f$request)
  for (eligible in list(FALSE, NA, NULL, 1, c(TRUE, TRUE))) {
    expect_error(
      artifact_reuse(f$store, "topic", accepted$id, "research", eligible),
      class = "graft_artifact_error"
    )
  }
  expect_error(
    artifact_reuse(f$store, "topic", accepted$id, "other", TRUE),
    class = "graft_artifact_error"
  )
  expect_error(
    decision_submit(
      f$request,
      key = "withdraw",
      expected = accepted$id,
      action = "withdraw",
      purpose = "other"
    ),
    class = "graft_artifact_error"
  )
  expect_error(
    decision_submit(
      f$request,
      key = "withdraw",
      expected = accepted$id,
      action = "withdraw",
      selection = f$correction
    ),
    class = "graft_artifact_error"
  )
  expect_length(decision_journal_files(f$store), 1L)
})

test_that("corrupt content blocks acceptance and reuse but permits withdrawal", {
  f <- local_decision_fixture()
  accepted <- decision_submit(f$request)
  payload <- artifact_read(f$store, f$first)$metadata$payload
  writeBin(charToRaw("changed"), file.path((f$store)@path, "content", payload))
  expect_error(
    decision_submit(f$request, key = "review-2", expected = accepted$id),
    class = "graft_artifact_error"
  )
  expect_error(
    artifact_reuse(f$store, "topic", accepted$id, "research", TRUE),
    class = "graft_artifact_error"
  )
  expect_identical(
    artifact_read_decision(f$store, "topic", accepted$id),
    accepted
  )
  withdrawn <- decision_submit(
    f$request,
    key = "withdraw",
    expected = accepted$id,
    action = "withdraw"
  )
  expect_identical(withdrawn$previous, accepted$id)
  expect_identical(decision_submit(f$request), accepted)
  expect_identical(artifact_read_decision(f$store, "topic"), withdrawn)
})

test_that("journal and selection limits are independent and enforced before writes", {
  f <- local_decision_fixture()
  for (limit in list(0, -1, 1.5, NA_real_, Inf, "large", numeric())) {
    expect_error(
      decision_submit(f$request, max_decisions = limit),
      class = "graft_artifact_error"
    )
    expect_error(
      decision_submit(f$request, max_metadata_bytes = limit),
      class = "graft_artifact_error"
    )
  }
  expect_error(
    decision_submit(f$request, max_metadata_bytes = 10),
    class = "graft_artifact_error"
  )
  expect_error(
    decision_submit(f$request, max_artifacts = 1),
    class = "graft_artifact_error"
  )
  expect_error(
    decision_submit(f$request, max_selection_bytes = 1),
    class = "graft_artifact_error"
  )
  expect_length(decision_journal_files(f$store), 0L)
  accepted <- decision_submit(f$request, max_decisions = 1)
  expect_identical(decision_submit(f$request, max_decisions = 1), accepted)
  size <- file.info(decision_journal_files(f$store))$size
  expect_identical(
    artifact_read_decision(f$store, "topic", max_metadata_bytes = size),
    accepted
  )
  expect_error(
    artifact_read_decision(
      f$store,
      "topic",
      max_metadata_bytes = size - 1
    ),
    class = "graft_artifact_error"
  )
  expect_error(
    decision_submit(
      f$request,
      key = "review-2",
      expected = accepted$id,
      max_decisions = 1
    ),
    class = "graft_artifact_error"
  )
  expect_error(
    decision_submit(
      f$request,
      key = "review-2",
      expected = accepted$id,
      max_metadata_bytes = size
    ),
    class = "graft_artifact_error"
  )
  expect_length(decision_journal_files(f$store), 1L)
  second <- decision_submit(f$request, key = "review-2", expected = accepted$id)
  expect_identical(second$sequence, 2L)
  expect_error(
    artifact_read_decision(f$store, "topic", max_decisions = 1),
    class = "graft_artifact_error"
  )
})

test_that("journal corruption, forks and gaps fail closed", {
  f <- local_decision_fixture()
  first <- decision_submit(f$request)
  decision_submit(f$request, key = "review-2", expected = first$id)
  paths <- decision_journal_files(f$store)
  bytes <- readBin(paths[[1]], "raw", n = file.info(paths[[1]])$size)
  writeBin(charToRaw("corrupt"), paths[[1]])
  expect_error(
    artifact_read_decision(f$store, "topic"),
    class = "graft_artifact_error"
  )
  writeBin(bytes, paths[[1]])
  fork <- file.path(
    dirname(paths[[1]]),
    paste0("0000000001-", strrep("0", 64), ".json")
  )
  file.copy(paths[[1]], fork)
  expect_error(
    artifact_read_decision(f$store, "topic"),
    class = "graft_artifact_error"
  )
  unlink(fork)
  unlink(paths[[1]])
  expect_error(
    artifact_read_decision(f$store, "topic"),
    class = "graft_artifact_error"
  )
})

test_that("staging is never promoted and failed publication can be retried", {
  f <- local_decision_fixture()
  local_mocked_bindings(artifact_rename_file = function(from, to) FALSE)
  expect_error(decision_submit(f$request), class = "graft_artifact_error")
  expect_null(artifact_read_decision(f$store, "topic"))
  staging <- file.path(
    artifact_decision_path(f$store, "topic"),
    "staged-interrupted"
  )
  writeBin(charToRaw("incomplete"), staging)
  expect_null(artifact_read_decision(f$store, "topic"))
  local_mocked_bindings(artifact_rename_file = function(from, to) {
    file.rename(from, to)
  })
  accepted <- decision_submit(f$request)
  expect_identical(artifact_read_decision(f$store, "topic"), accepted)
  expect_identical(readBin(staging, "raw", n = 10), charToRaw("incomplete"))
})

test_that("lost replies after publication do not duplicate or reapprove decisions", {
  f <- local_decision_fixture()
  local_mocked_bindings(artifact_rename_file = function(from, to) {
    file.rename(from, to)
    artifact_abort("Simulated interruption after publication.")
  })
  expect_error(decision_submit(f$request), class = "graft_artifact_error")
  reopened <- graft_store((f$store)@path)
  accepted <- artifact_read_decision(reopened, "topic")
  expect_identical(decision_submit(f$request), accepted)
  expect_length(decision_journal_files(f$store), 1L)
  local_mocked_bindings(artifact_rename_file = function(from, to) {
    file.rename(from, to)
  })
  withdrawn <- decision_submit(
    f$request,
    key = "withdraw",
    expected = accepted$id,
    action = "withdraw"
  )
  expect_identical(decision_submit(f$request), accepted)
  expect_identical(artifact_read_decision(reopened, "topic"), withdrawn)
})

test_that("decisions and guarded consultation survive a fresh R process", {
  f <- local_decision_fixture()
  accepted <- decision_submit(f$request)
  result <- callr::r(
    function(path, id, checkout) {
      if (!is.null(checkout)) {
        pkgload::load_all(checkout, quiet = TRUE)
      }
      store <- graft::graft_store(path)
      graft:::artifact_reuse(store, "topic", id, "research", TRUE)
    },
    list(
      path = (f$store)@path,
      id = accepted$id,
      checkout = if (pkgload::is_dev_package("graft")) {
        normalizePath("../..")
      } else {
        NULL
      }
    )
  )
  expect_identical(result$decision, accepted)
  expect_identical(result$selection$artifacts, list(f$first, f$source))
})

test_that("decisions from two processes in one stream never fork the journal", {
  f <- local_decision_fixture()
  go <- file.path(dirname(f$store@path), "go")
  args <- list(
    path = f$store@path,
    stream = "topic",
    selection = f$selection,
    rounds = 15L,
    go = go,
    checkout = graft_checkout()
  )
  workers <- lapply(c("a", "b"), function(prefix) {
    callr::r_bg(decision_race_worker, c(args, prefix = prefix))
  })
  file.create(go)
  for (worker in workers) {
    worker$wait(60000)
  }
  done <- vapply(workers, \(worker) worker$get_result(), integer(1))
  expect_identical(done, c(15L, 15L))
  records <- artifact_decisions(f$store, "topic", 1000L, 1024^2)
  expect_length(records, 30L)
  expect_identical(
    vapply(records, \(x) x$sequence, integer(1)),
    seq_len(30L)
  )
})

test_that("a decision waits for the stream lock, then fails as busy", {
  f <- local_decision_fixture()
  store <- graft_store(f$store@path, lock_timeout = 0.2)
  lock_path <- file.path(
    store@path,
    "locks",
    paste0(artifact_sha(charToRaw("topic")), ".lock")
  )
  dir.create(dirname(lock_path))
  held <- file.path(dirname(store@path), "held")
  holder <- callr::r_bg(
    function(lock_path, held) {
      lock <- filelock::lock(lock_path)
      file.create(held)
      Sys.sleep(5)
      filelock::unlock(lock)
    },
    list(lock_path = lock_path, held = held)
  )
  withr::defer(holder$kill())
  while (!file.exists(held)) {
    Sys.sleep(0.01)
  }
  expect_error(
    decision_submit(utils::modifyList(f$request, list(store = store))),
    class = "graft_store_busy_error"
  )
  expect_null(artifact_read_decision(store, "topic"))
  holder$kill()
  expect_identical(
    decision_submit(utils::modifyList(f$request, list(store = store)))$key,
    "review-1"
  )
})

test_that("head changes during verification cannot silently authorize new work", {
  f <- local_decision_fixture()
  original <- artifact_read_selection
  intervened <- FALSE
  local_mocked_bindings(artifact_read_selection = function(...) {
    result <- original(...)
    if (!intervened) {
      intervened <<- TRUE
      decision_submit(f$request, key = "intervening")
    }
    result
  })
  expect_error(decision_submit(f$request), class = "graft_artifact_error")
  head <- artifact_read_decision(f$store, "topic")
  expect_identical(head$key, "intervening")
  local_mocked_bindings(artifact_read_selection = function(...) {
    result <- original(...)
    decision_submit(
      f$request,
      key = "withdraw",
      expected = head$id,
      action = "withdraw"
    )
    result
  })
  expect_error(
    artifact_reuse(f$store, "topic", head$id, "research", TRUE),
    class = "graft_artifact_error"
  )
  expect_identical(
    artifact_read_decision(f$store, "topic")$action,
    "withdraw"
  )
})

test_that("a lock directory another process created first is used", {
  f <- local_decision_fixture()
  unlink(file.path(f$store@path, "locks"), recursive = TRUE)
  withr::local_options(warn = 2)
  local_mocked_bindings(artifact_create_dir = function(path) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
    FALSE
  })
  expect_identical(decision_submit(f$request)$key, "review-1")
})

test_that("an accept that times out on the lock writes no selection", {
  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE, lock_timeout = 0.2)
  ref <- graft_save(store, "kept", "note")
  lock_path <- file.path(
    path,
    "locks",
    paste0(artifact_sha(charToRaw("topic")), ".lock")
  )
  dir.create(dirname(lock_path))
  held <- file.path(dirname(path), "held-accept")
  holder <- callr::r_bg(
    function(lock_path, held) {
      lock <- filelock::lock(lock_path)
      file.create(held)
      Sys.sleep(5)
      filelock::unlock(lock)
    },
    list(lock_path = lock_path, held = held)
  )
  withr::defer(holder$kill())
  while (!file.exists(held)) {
    Sys.sleep(0.01)
  }
  selections <- function() {
    list.files(file.path(path, "selections"), recursive = TRUE)
  }
  before <- selections()
  expect_error(
    graft_accept(
      store,
      ref,
      stream = "topic",
      expected = NULL,
      key = "keep-1",
      actor = "reviewer",
      reason = "kept",
      purpose = "research"
    ),
    class = "graft_store_busy_error"
  )
  expect_identical(selections(), before)
})
