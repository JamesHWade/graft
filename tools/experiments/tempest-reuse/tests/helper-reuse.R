checkout <- getOption("graft.experiment.checkout")
for (file in c(
  "artifacts/content.R",
  "artifacts/backends.R",
  "tempest-migration/migration.R",
  "tempest-reuse/reuse.R"
)) {
  source(file.path(checkout, "tools/experiments", file))
}
reuse_fixture <- getOption("graft.reuse.fixture")

reuse_order_object_members <- function(value) {
  if (!is.list(value)) {
    return(value)
  }
  if (!is.null(names(value))) {
    value <- value[order(names(value), method = "radix")]
  }
  lapply(value, reuse_order_object_members)
}
