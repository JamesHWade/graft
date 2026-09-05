#!/usr/bin/env Rscript
# Installation belongs to the caller. Optionally use a maintained dsprrr checkout.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) > 1L) {
  stop("Supply at most one dsprrr checkout path.")
}
devtools::load_all()
if (length(arguments) == 1L) {
  pkgload::load_all(arguments[[1L]])
}
if (!requireNamespace("dsprrr", quietly = TRUE)) {
  stop("Install dsprrr first.")
}
local({
  store <- graft::graft_open(
    graft::graft_schema(system.file(
      "extdata/team-directory.data-dict.json",
      package = "graft",
      mustWork = TRUE
    )),
    okf = "disabled"
  )
  on.exit(graft::graft_close(store))
  type <- graft::graft_proposal_type(store, tables = "person")
  signature <- dsprrr::signature(
    inputs = list(text = dsprrr::input("text", description = "Source text")),
    output_type = type
  )
  stopifnot(identical(signature@output_type, type))
  message(
    "dsprrr ",
    utils::packageVersion("dsprrr"),
    " accepts the public proposal type."
  )
})
