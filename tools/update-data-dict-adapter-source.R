args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L || (length(args) == 1L && args != "--check")) {
  stop("Usage: Rscript tools/update-data-dict-adapter-source.R [--check]")
}

check <- identical(args, "--check")
root <- normalizePath(".", winslash = "/", mustWork = TRUE)
if (!file.exists(file.path(root, "DESCRIPTION"))) {
  stop("Run this script from the Graft package root.")
}

devtools::load_all(root, quiet = TRUE)
payload <- graft:::data_dict_adapter_source_payload()
bytes <- charToRaw(enc2utf8(graft:::canonical_json(payload)))
path <- file.path(
  root,
  "inst",
  "schema",
  "graft-data-dict-adapter.source.json"
)

if (check) {
  if (!file.exists(path)) {
    stop("The committed data-dict adapter source artifact is missing.")
  }
  observed <- readBin(path, what = "raw", n = file.info(path)$size)
  if (!identical(observed, bytes)) {
    stop(
      paste(
        "The committed data-dict adapter source artifact is stale.",
        "Run this script without --check to regenerate it."
      )
    )
  }
  message("The committed data-dict adapter source artifact is current.")
} else {
  writeBin(bytes, path)
  message("Updated ", path, ".")
}
