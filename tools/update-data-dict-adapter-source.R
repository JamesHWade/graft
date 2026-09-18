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

schema_path <- file.path(root, "inst", "schema", "graft-manifest.schema.json")
schema_lines <- readLines(schema_path, warn = FALSE)
schema <- jsonlite::fromJSON(
  paste(schema_lines, collapse = "\n"),
  simplifyVector = FALSE
)
schema_digest <- schema$allOf[[
  1L
]]$then$properties$compiler$properties$script_digest$const
expected_digest <- graft:::graft_sha256(bytes)
stopifnot(is.character(schema_digest), length(schema_digest) == 1L)

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
  if (!identical(schema_digest, expected_digest)) {
    stop(
      "The manifest schema adapter digest is stale. Run this script without --check."
    )
  }
  message(
    "The committed data-dict adapter source and manifest schema are current."
  )
} else {
  writeBin(bytes, path)
  writeLines(
    gsub(schema_digest, expected_digest, schema_lines, fixed = TRUE),
    schema_path
  )
  message("Updated ", path, " and ", schema_path, ".")
}
