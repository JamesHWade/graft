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
