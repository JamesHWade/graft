artifact_backup_validation_clone <- function(path, parent, name) {
  target <- file.path(parent, name)
  if (!dir.create(target)) {
    stop("Could not create validation bundle clone.")
  }
  entries <- list.files(
    path,
    all.files = TRUE,
    no.. = TRUE,
    full.names = TRUE
  )
  copied <- file.copy(entries, target, recursive = TRUE)
  if (!all(copied)) {
    stop("Could not copy validation bundle.")
  }
  target
}

artifact_backup_validation_descriptor <- function(path) {
  descriptor_path <- file.path(path, "bundle.json")
  descriptor_bytes <- readBin(
    descriptor_path,
    what = "raw",
    n = file.info(descriptor_path)$size
  )
  list(
    value = artifact_decode(descriptor_bytes),
    bytes = descriptor_bytes
  )
}

artifact_backup_validation_write_descriptor <- function(
  path,
  descriptor,
  scope = "reader-a",
  generation = "generation-1",
  manifest = strrep("0", 64),
  bytes = artifact_encode(descriptor)
) {
  writeBin(bytes, file.path(path, "bundle.json"))
  list(
    format = "graft-artifact-backup/1",
    id = digest::digest(bytes, algo = "sha256", serialize = FALSE),
    scope = scope,
    generation = generation,
    manifest = manifest
  )
}
