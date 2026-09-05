reuse_example <- function() {
  env <- new.env(parent = environment())
  sys.source(system.file("examples/reuse-basis.R", package = "graft"), env)
  env
}

reuse_consumer_selection <- function(consumer) {
  if (consumer == "research") {
    list(
      roots = "knowledge:conclusion",
      dependencies = data.frame(
        outcome = c("knowledge:conclusion", "support:conclusion"),
        dependency = c("support:conclusion", "source:trial-v1")
      )
    )
  } else {
    list(
      roots = c("knowledge:interpretation", "knowledge:preference"),
      dependencies = data.frame(
        outcome = c("knowledge:interpretation", "support:interpretation"),
        dependency = c("support:interpretation", "source:trial-v1")
      )
    )
  }
}

capture_consumer_basis <- function(store, consumer = "reading") {
  selection <- reuse_consumer_selection(consumer)
  reuse_example()$capture_reuse_basis(
    store,
    selection$roots,
    selection$dependencies
  )
}
