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
    initial = "sha256:b19dedc6127d20c515af3bcb9bae9c960bb04cf4a05af5ffafa259f7acf8c43d",
    correction = "sha256:55485f222bdcaf8aa7fa3233184029fb7aad472cfcee4a01250f727f3c5cbc1a"
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
