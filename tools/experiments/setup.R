# Network-enabled provisioning only. The experiment runner does not install.
# Required: GRAFT_EXPERIMENT_HOME, an isolated writable dependency directory.
experiment_home <- Sys.getenv("GRAFT_EXPERIMENT_HOME")
if (!nzchar(experiment_home)) {
  stop(
    "Set GRAFT_EXPERIMENT_HOME to an isolated dependency directory.",
    call. = FALSE
  )
}
dir.create(experiment_home, recursive = TRUE, showWarnings = FALSE)
experiment_home <- normalizePath(experiment_home, winslash = "/")
experiment_library <- file.path(experiment_home, "library")
dir.create(experiment_library, showWarnings = FALSE)
.libPaths(c(experiment_library, .libPaths()))
options(repos = c(CRAN = "https://cloud.r-project.org"))
skip_r <- identical(Sys.getenv("GRAFT_EXPERIMENT_SKIP_R_INSTALL"), "true")

# Bootstrap into this library only; CI already supplies these through pak.
for (package in c("jsonlite", "pak")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    if (skip_r) {
      stop("Missing setup dependency: ", package, call. = FALSE)
    }
    utils::install.packages(package, lib = experiment_library)
  }
}
pins <- jsonlite::read_json(
  "tools/experiments/pins.json",
  simplifyVector = FALSE
)
stopifnot(identical(pins$schema_version, 1L))
package_ref <- function(pin) {
  path <- paste0(
    pin$repository,
    if (nzchar(pin$subdir)) paste0("/", pin$subdir)
  )
  paste0(path, "@", pin$sha)
}
if (!skip_r) {
  pak::pkg_install(
    c(
      vapply(pins$packages, package_ref, character(1)),
      unlist(pins$extra_packages),
      paste0("local::", normalizePath("."))
    ),
    lib = experiment_library,
    dependencies = c("Depends", "Imports", "LinkingTo"),
    ask = FALSE,
    upgrade = FALSE
  )
}
# A version number alone cannot verify a development package's source.
for (pin in pins$packages) {
  if (!file.exists(file.path(experiment_library, pin$package, "DESCRIPTION"))) {
    stop(
      "Missing pinned package in the isolated library: ",
      pin$package,
      call. = FALSE
    )
  }
  description <- utils::packageDescription(
    pin$package,
    lib.loc = experiment_library
  )
  if (
    !identical(description$RemoteSha, pin$sha) ||
      !identical(description$Version, pin$version)
  ) {
    stop("Pinned source/version mismatch for ", pin$package, call. = FALSE)
  }
}
if (!file.exists(file.path(experiment_library, "graft", "DESCRIPTION"))) {
  stop(
    "The current graft checkout must be installed in the isolated library.",
    call. = FALSE
  )
}

cli_pin <- Filter(
  \(pin) identical(pin$package, pins$data_dict_cli_package),
  pins$packages
)[[1]]
source_dir <- file.path(experiment_home, paste0("data-dict-", cli_pin$sha))
if (!dir.exists(source_dir)) {
  archive <- tempfile(fileext = ".tar.gz")
  utils::download.file(
    paste0(
      "https://api.github.com/repos/",
      cli_pin$repository,
      "/tarball/",
      cli_pin$sha
    ),
    archive,
    mode = "wb",
    quiet = TRUE
  )
  unpack <- tempfile("data-dict-source-", tmpdir = experiment_home)
  dir.create(unpack)
  utils::untar(archive, exdir = unpack)
  roots <- list.dirs(unpack, full.names = TRUE, recursive = FALSE)
  if (length(roots) != 1L || !file.exists(file.path(roots, "Cargo.lock"))) {
    stop(
      "Pinned data-dict archive has no unique Cargo source root.",
      call. = FALSE
    )
  }
  if (!file.rename(roots, source_dir)) {
    stop("Could not move data-dict source.", call. = FALSE)
  }
  unlink(c(unpack, archive), recursive = TRUE)
}
cargo <- Sys.which("cargo")
if (!nzchar(cargo)) {
  stop("Install Rust/cargo before provisioning the CLI.", call. = FALSE)
}
build_cli <- function() {
  previous <- setwd(source_dir)
  on.exit(setwd(previous), add = TRUE)
  status <- system2(
    cargo,
    c("build", "--release", "--locked", "-p", "data-dict-cli")
  )
  if (!identical(status, 0L)) {
    stop("Pinned data-dict build failed.", call. = FALSE)
  }
}
build_cli()
binary_name <- if (.Platform$OS.type == "windows") {
  "data-dict.exe"
} else {
  "data-dict"
}
dir.create(file.path(experiment_home, "bin"), showWarnings = FALSE)
binary <- file.path(experiment_home, "bin", binary_name)
if (
  !file.copy(
    file.path(source_dir, "target", "release", binary_name),
    binary,
    overwrite = TRUE
  )
) {
  stop("Could not preserve the built CLI.", call. = FALSE)
}
Sys.chmod(binary, "0755")
Sys.setenv(DATA_DICT = binary)
cli_version <- datadict::dd_run("--version")$output
if (!identical(cli_version, paste("data-dict", pins$data_dict_cli_version))) {
  stop("Unexpected data-dict CLI version.", call. = FALSE)
}

# Source this file for local interactive use, or export the printed paths.
environment_file <- file.path(experiment_home, "environment.R")
writeLines(
  c(
    paste0(
      ".libPaths(c(",
      encodeString(experiment_library, quote = '"'),
      ", .libPaths()))"
    ),
    paste0("Sys.setenv(DATA_DICT = ", encodeString(binary, quote = '"'), ")")
  ),
  environment_file
)
installed <- as.data.frame(
  utils::installed.packages(lib.loc = experiment_library)[,
    c("Package", "Version"),
    drop = FALSE
  ],
  stringsAsFactors = FALSE
)
jsonlite::write_json(
  list(
    source_pins = pins,
    packages = installed,
    R = R.version.string,
    cli = cli_version,
    cli_sha256 = unname(cli::hash_file_sha256(binary)),
    cargo = system2(cargo, "--version", stdout = TRUE)
  ),
  file.path(experiment_home, "versions.json"),
  pretty = TRUE,
  auto_unbox = TRUE
)
if (nzchar(Sys.getenv("GITHUB_ENV"))) {
  cat(
    paste0("DATA_DICT=", binary, "\n"),
    file = Sys.getenv("GITHUB_ENV"),
    append = TRUE
  )
}
cat("Setup complete. Source ", environment_file, " or use:\n", sep = "")
cat("R_LIBS_USER=", experiment_library, "\nDATA_DICT=", binary, "\n", sep = "")
