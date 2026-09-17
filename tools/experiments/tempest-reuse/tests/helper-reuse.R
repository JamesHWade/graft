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

reuse_source_bindings <- function(sources) {
  ids <- vapply(
    sources[["meta"]],
    \(meta) meta[["artifact_record_id"]],
    character(1)
  )
  stats::setNames(
    lapply(seq_len(nrow(sources)), function(i) {
      metadata <- sources[["meta"]][[i]]
      list(
        record_id = metadata[["artifact_record_id"]],
        revision_id = metadata[["artifact_revision_id"]],
        class = metadata[["artifact_record_class"]],
        content = sources[["content_text"]][[i]]
      )
    }),
    ids
  )
}
