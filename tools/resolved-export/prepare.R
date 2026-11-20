# Network/build preparation is deliberately separate from the offline tests.
prepare_resolved_fixture <- function(args) {
  if (length(args) != 1L) {
    stop(
      "Usage: Rscript --vanilla tools/resolved-export/prepare.R CACHE_DIRECTORY"
    )
  }
  script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  fixture <- dirname(normalizePath(script))
  source(file.path(fixture, "runtime.R"), local = TRUE)
  pins <- jsonlite::read_json(file.path(fixture, "pins.json"))
  dir.create(args[[1L]], recursive = TRUE, showWarnings = FALSE)
  cache <- normalizePath(args[[1L]], mustWork = TRUE)
  for (name in names(pins$sources)) {
    pin <- pins$sources[[name]]
    archive <- file.path(cache, pin$archive)
    if (!file.exists(archive)) {
      staging <- tempfile("source-", tmpdir = cache)
      tryCatch(
        {
          utils::download.file(pin$url, staging, mode = "wb", quiet = TRUE)
          if (!identical(resolved_runtime_digest(staging), pin$sha256)) {
            resolved_runtime_abort(paste(
              "Downloaded archive differs from its pin:",
              name
            ))
          }
          if (!file.rename(staging, archive)) {
            resolved_runtime_abort(paste(
              "Cannot publish source archive:",
              name
            ))
          }
        },
        finally = unlink(staging)
      )
    }
    resolved_runtime_archive(cache, pin)
    cat(name, pin$commit, "archive verified\n")
  }
  if (file.exists(file.path(cache, "cli.json"))) {
    resolved_runtime_cli(cache, pins)
    cat("Prepared CLI verified; no rebuild needed.\n")
    return(invisible(cache))
  }
  rust <- processx::run("rustc", "--version", timeout = 10000)$stdout
  if (
    !identical(strsplit(trimws(rust), " ", fixed = TRUE)[[1L]][[2L]], pins$rust)
  ) {
    resolved_runtime_abort(paste("CLI preparation requires Rust", pins$rust))
  }
  extraction <- tempfile("build-source-", tmpdir = cache)
  dir.create(extraction)
  on.exit(unlink(extraction, recursive = TRUE), add = TRUE)
  source_root <- resolved_runtime_unpack(
    resolved_runtime_archive(cache, pins$sources$datadict),
    file.path(extraction, "datadict")
  )
  if (
    Sys.info()[["sysname"]] == "Darwin" &&
      !nzchar(Sys.getenv("DEVELOPER_DIR")) &&
      dir.exists("/Library/Developer/CommandLineTools")
  ) {
    withr::local_envvar(c(
      DEVELOPER_DIR = "/Library/Developer/CommandLineTools"
    ))
  }
  target <- file.path(cache, "target")
  cat("Building the pinned data-dict CLI with locked dependencies...\n")
  result <- processx::run(
    "cargo",
    c(
      "build",
      "--release",
      "--locked",
      "--manifest-path",
      file.path(source_root, "Cargo.toml"),
      "-p",
      "data-dict-cli",
      "--target-dir",
      target
    ),
    stdout = file.path(cache, "cargo.stdout.log"),
    stderr = file.path(cache, "cargo.stderr.log"),
    error_on_status = FALSE,
    timeout = 1800000
  )
  if (result$status != 0L) {
    cat(
      tail(readLines(file.path(cache, "cargo.stderr.log"), warn = FALSE), 50L),
      sep = "\n"
    )
    resolved_runtime_abort("Pinned CLI build failed; see the preparation logs.")
  }
  dir.create(file.path(cache, "bin"), showWarnings = FALSE)
  binary <- file.path(cache, "bin", "data-dict")
  if (
    !file.copy(
      file.path(target, "release", "data-dict"),
      binary,
      overwrite = TRUE
    )
  ) {
    resolved_runtime_abort("Cannot copy the prepared CLI.")
  }
  Sys.chmod(binary, mode = "0755")
  version <- trimws(processx::run(binary, "--version", timeout = 10000)$stdout)
  if (!identical(version, pins$cli_version)) {
    resolved_runtime_abort("Built CLI version differs from the source pin.")
  }
  record <- list(
    format = 1L,
    source_commit = pins$sources$datadict$commit,
    source_archive_sha256 = pins$sources$datadict$sha256,
    cargo_lock_sha256 = resolved_runtime_digest(file.path(
      source_root,
      "Cargo.lock"
    )),
    binary_sha256 = resolved_runtime_digest(binary),
    cli_version = version,
    rust = pins$rust,
    rustc = trimws(rust),
    platform = as.list(Sys.info()[c("sysname", "machine")])
  )
  jsonlite::write_json(
    record,
    file.path(cache, "cli.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  resolved_runtime_cli(cache, pins)
  cat("CLI built and locally recorded:", record$binary_sha256, "\n")
}

prepare_resolved_fixture(commandArgs(trailingOnly = TRUE))
