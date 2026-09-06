reader_access_example <- function() {
  env <- new.env(parent = environment())
  sys.source(system.file("examples/reader-access.R", package = "graft"), env)
  env
}

local_reader_access <- function(.local_envir = parent.frame()) {
  example <- reader_access_example()
  directory <- withr::local_tempdir(.local_envir = .local_envir)
  locations <- example$reader_access_fixture(directory)
  grants <- new.env(parent = emptyenv())
  grants$alice <- "alice-grant-1"
  grants$bob <- "bob-grant-1"
  bind <- function(reader) {
    example$reader_knowledge_access(
      reader,
      locate = \(reader) locations[[reader]],
      grant = \(reader) grants[[reader]]
    )
  }
  list(
    example = example,
    locations = locations,
    grants = grants,
    bind = bind,
    alice = bind("alice"),
    bob = bind("bob")
  )
}
