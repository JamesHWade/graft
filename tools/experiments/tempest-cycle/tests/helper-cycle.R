cycle_fixture <- getOption("graft.cycle.fixture")
source(file.path(
  cycle_fixture$checkout,
  "tools/experiments/tempest-cycle/host.R"
))
cycle_load(cycle_fixture$checkout, environment())
cycle_run <- function(backend, root, fn, ...) {
  lib <- if (backend == "manifest") {
    c(cycle_fixture$library, .Library)
  } else {
    .libPaths()
  }
  callr::r(
    function(checkout, root, backend, fn, args) {
      if (backend == "manifest") {
        stopifnot(!requireNamespace("graft", quietly = TRUE))
      }
      source(file.path(checkout, "tools/experiments/tempest-cycle/host.R"))
      cycle_load(checkout, globalenv())
      store <- artifact_store(
        root,
        backend,
        file.path(
          checkout,
          "tools/experiments/artifacts/artifact.data-dict.json"
        )
      )
      on.exit(artifact_close(store))
      value <- do.call(fn, c(list(store = store), args))
      if (backend == "manifest") {
        stopifnot(!"graft" %in% loadedNamespaces())
      }
      list(
        value = value,
        pid = Sys.getpid(),
        graft_available = requireNamespace("graft", quietly = TRUE)
      )
    },
    args = list(cycle_fixture$checkout, root, backend, fn, list(...)),
    libpath = lib
  )
}
cycle_stage_fixture <- function(store, name) {
  pins <- c(
    initial = "sha256:00e1323021683893220b0b919ce019933449d97d01a0da1e0ece858964cb1c86",
    correction = "sha256:8d12626a5a0c953211e77604357cba44b6359459d9dbd45d732deca86ce5204d"
  )
  fixture <- system.file("examples/accepted-research", package = "tempest")
  cycle_stage(
    store,
    file.path(fixture, name),
    unname(pins[[name]]),
    file.path(fixture, paste0(name, "-report.md"))
  )
}
# Serialize the fixture helper into each independent process explicitly.
cycle_stage_in_child <- function(store, name, stage) stage(store, name)
