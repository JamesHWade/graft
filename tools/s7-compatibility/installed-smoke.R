required_s7 <- Sys.getenv("S7_VERSION")
if (!nzchar(required_s7)) {
  stop("S7_VERSION must identify the version under qualification.")
}

installed_s7 <- as.character(utils::packageVersion("S7"))
if (!identical(installed_s7, required_s7)) {
  stop(
    "Expected S7 ",
    required_s7,
    ", but found S7 ",
    installed_s7,
    ".",
    call. = FALSE
  )
}

path <- tempfile("graft-installed-")
on.exit(unlink(path, recursive = TRUE), add = TRUE)

store <- graft::graft_store(path, create = TRUE)
ref <- graft::graft_save(store, "Installed-package dispatch", "note")
artifact <- graft::graft_read(store, ref)
decision <- graft::graft_accept(
  store,
  ref,
  stream = "stream",
  expected = NULL,
  key = "request",
  actor = "reviewer",
  reason = "checked",
  purpose = "qualification"
)
recall <- graft::graft_recall(
  store,
  stream = "stream",
  purpose = "qualification",
  eligible = TRUE
)

values <- list(
  ref = ref,
  artifact = artifact,
  selection = recall@selection,
  decision = decision,
  recall = recall
)
expected <- c(
  ref = "<ArtifactRef ",
  artifact = "<Artifact ",
  selection = "<ArtifactSelection ",
  decision = "<Decision ",
  recall = "<Recall status=accepted"
)

for (name in names(values)) {
  output <- capture.output(print(values[[name]]))
  if (!any(grepl(expected[[name]], output, fixed = TRUE))) {
    stop(
      "Installed-package print dispatch failed for ",
      name,
      ": ",
      paste(output, collapse = " "),
      call. = FALSE
    )
  }
}

cat(
  "Installed Graft print dispatch passed with S7 ",
  installed_s7,
  ".\n",
  sep = ""
)
