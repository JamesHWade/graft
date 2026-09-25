# A child process holds a store's lock (`locks/store.lock`) directly with
# filelock, as another graft process would, until the test kills it.
local_store_lock_holder <- function(store, exclusive, env = parent.frame()) {
  lock_path <- file.path(store@path, "locks", "store.lock")
  dir.create(dirname(lock_path), showWarnings = FALSE)
  held <- tempfile("held-")
  holder <- callr::r_bg(
    function(lock_path, held, exclusive) {
      lock <- filelock::lock(lock_path, exclusive = exclusive)
      file.create(held)
      Sys.sleep(30)
      filelock::unlock(lock)
    },
    list(lock_path = lock_path, held = held, exclusive = exclusive)
  )
  withr::defer(holder$kill(), envir = env)
  while (!file.exists(held)) {
    Sys.sleep(0.01)
  }
  holder
}

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
  expect_false(exists("ran", envir = state))

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
  expect_true(file.exists(file.path(store@path, "locks", "store.lock")))
  expect_no_error(graft_manifest(store))
})
