test_that("graft_with_store_lock() returns the value of its code", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  ref <- graft_with_store_lock(store, graft_save(store, "kept", "note"))
  expect_identical(graft_read(store, ref)@data, "kept")

  shared <- graft_with_store_lock(
    store,
    graft_save(store, "shared", "note"),
    exclusive = FALSE
  )
  expect_identical(graft_read(store, shared)@data, "shared")
  expect_length(
    graft_with_store_lock(store, graft_manifest(store)$objects),
    4L
  )
})

test_that("a whole-store operation cannot run inside a shared hold", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  expect_error(
    graft_with_store_lock(store, graft_manifest(store), exclusive = FALSE),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_with_store_lock(store, TRUE, exclusive = NA),
    class = "graft_artifact_error"
  )
  # The failed hold released the lock.
  expect_no_error(graft_manifest(store))
})

test_that("an exclusive hold keeps writes and manifests out", {
  path <- withr::local_tempdir()
  graft_store(path, create = TRUE)
  store <- graft_store(path, lock_timeout = 0.2)
  holder <- local_store_lock_holder(store, exclusive = TRUE)

  expect_error(
    graft_save(store, "blocked", "note"),
    class = "graft_store_busy_error"
  )
  expect_error(graft_manifest(store), class = "graft_store_busy_error")
  state <- new.env()
  expect_error(
    graft_with_store_lock(store, assign("ran", TRUE, envir = state)),
    class = "graft_store_busy_error"
  )
  expect_identical(ls(state), character())

  holder$kill()
  ref <- graft_save(store, "after", "note")
  expect_identical(graft_read(store, ref)@data, "after")
})

test_that("writers share the lock, and a manifest waits for them", {
  path <- withr::local_tempdir()
  graft_store(path, create = TRUE)
  store <- graft_store(path, lock_timeout = 0.2)
  holder <- local_store_lock_holder(store, exclusive = FALSE)

  ref <- graft_save(store, "alongside", "note")
  expect_identical(graft_read(store, ref)@data, "alongside")
  expect_error(graft_manifest(store), class = "graft_store_busy_error")
  expect_error(
    graft_plan_replacement(store, list(ref)),
    class = "graft_store_busy_error"
  )

  holder$kill()
  expect_length(graft_manifest(store)$objects, 2L)
})

test_that("the store lock file passes the manifest's lock directory check", {
  store <- graft_store(withr::local_tempdir(), create = TRUE)
  graft_save(store, "kept", "note")
  expect_contains(list.files(file.path(store@path, "locks")), "store.lock")
  expect_no_error(graft_manifest(store))
})

test_that("a decision takes the store lock before its stream lock", {
  f <- local_decision_fixture()
  store <- graft_store(f$store@path, lock_timeout = 0.2)
  # Taken in the other order, a writer could hold the stream lock while it
  # waits for the store's, and an exclusive holder deciding in that stream
  # would wait for it in turn.
  holder <- local_store_lock_holder(store, exclusive = TRUE)
  expect_error(
    decision_submit(utils::modifyList(f$request, list(store = store))),
    class = "graft_store_busy_error"
  )
  expect_identical(
    list.files(file.path(store@path, "locks")),
    "store.lock"
  )
})
