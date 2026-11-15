# Fetch immutable upstream source archives. Tests themselves do not use the network.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Usage: Rscript tools/output-handoff/prepare.R CACHE_DIRECTORY")
}
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
pins <- jsonlite::fromJSON(
  file.path(dirname(normalizePath(script)), "pins.json"),
  simplifyVector = FALSE
)
cache <- args[[1L]]
dir.create(cache, recursive = TRUE, showWarnings = FALSE)
for (name in names(pins$sources)) {
  pin <- pins$sources[[name]]
  archive <- file.path(cache, pin$archive)
  if (!file.exists(archive)) {
    staging <- tempfile(paste0(name, "-"), tmpdir = cache)
    tryCatch(
      {
        utils::download.file(pin$url, staging, mode = "wb", quiet = TRUE)
        if (
          !identical(
            digest::digest(file = staging, algo = "sha256"),
            pin$sha256
          )
        ) {
          stop("Source archive digest differs from the pin: ", name)
        }
        if (!file.rename(staging, archive)) {
          stop("Could not publish the source archive: ", name)
        }
      },
      finally = unlink(staging)
    )
  }
  if (!identical(digest::digest(file = archive, algo = "sha256"), pin$sha256)) {
    stop("Cached source archive digest differs from the pin: ", name)
  }
  cat(name, pin$commit, "verified\n")
}
