blob_class <- "graft_blob"
blob_id_pattern <- "^sha256:[0-9a-f]{64}$"

#' Stage bytes as a content-addressed blob
#'
#' A contract that declares a `graft_blob` table can hold files beside its
#' records. `graft_blob()` writes the bytes into the store's blob directory,
#' named by their SHA-256 digest, and returns the one-row `graft_blob` record
#' that refers to them. Supply that row to [graft_plan()] with the records
#' that reference its `id`, so the bytes and the references are reviewed and
#' committed together. Identical bytes are stored once.
#'
#' The `graft_blob` table must have a string `id` primary key, a required
#' string `media_type`, and a required numeric `size_bytes`. Planning fails
#' when a blob row's bytes are missing, differ in size or digest, or when a
#' committed blob would change.
#'
#' @param store An initialized, writable `GraftStore`.
#' @param x A raw vector, or the path to one file.
#' @param media_type The media type of the bytes, such as `"image/png"`.
#'
#' @return A one-row data frame with `id`, `media_type`, and `size_bytes`.
#' @examples
#' dictionary <- system.file(
#'   "extdata",
#'   "artifacts.data-dict.json",
#'   package = "graft",
#'   mustWork = TRUE
#' )
#' store <- graft_open(graft_schema(dictionary), okf = "disabled")
#' graft_blob(store, charToRaw("<p>Hello</p>"), "text/html")
#' graft_close(store)
#' @export
graft_blob <- function(store, x, media_type) {
  store <- as_graft_store_internal(store, "store")
  validate_initialized_store(store, write = TRUE)
  validate_store_writable(store, "graft_blob")
  require_blob_contract(store)
  bytes <- blob_input_bytes(x)
  media_type <- validate_media_type(media_type)
  hex <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
  write_blob_bytes(store, hex, bytes)
  data.frame(
    id = paste0("sha256:", hex),
    media_type = media_type,
    size_bytes = as.double(length(bytes)),
    stringsAsFactors = FALSE
  )
}

#' Read the bytes of a committed blob
#'
#' The bytes are returned only when a committed `graft_blob` record names
#' them, and only after their size and SHA-256 digest match that record.
#'
#' @param store An initialized `GraftStore`.
#' @param id A blob id returned by [graft_blob()].
#'
#' @return A raw vector.
#' @export
graft_blob_read <- function(store, id) {
  store <- as_graft_store_internal(store, "store")
  validate_initialized_store(store)
  require_blob_contract(store)
  id <- validate_blob_id(id)
  row <- graft_current_rows(store, ids = id, classes = blob_class, limit = 1L)
  if (nrow(row) == 0L) {
    abort_reference_error(
      paste0("Blob `", id, "` has no committed `graft_blob` record."),
      record_id = id,
      field = "id",
      rule = "record_exists",
      observed_value = id
    )
  }
  record <- graft_public_current_record(store, row[1L, , drop = FALSE])
  expected_size <- record$size_bytes[[1L]]
  problem <- blob_bytes_problem(store, id, expected_size)
  if (!is.null(problem)) {
    abort_blob_error(problem$message, record_id = id, rule = problem$rule)
  }
  path <- blob_file(store, blob_hex(id))
  readBin(path, "raw", n = file.size(path))
}

validate_blob_contract <- function(manifest) {
  if (!blob_class %in% names(manifest$classes)) {
    return(invisible(manifest))
  }
  requirements <- list(
    id = list(range = "string", identifier = TRUE),
    media_type = list(range = "string", required = TRUE),
    size_bytes = list(range = "double", required = TRUE)
  )
  for (name in names(requirements)) {
    slot <- manifest$slots[[paste0(blob_class, ".", name)]]
    wanted <- requirements[[name]]
    ok <- !is.null(slot) &&
      identical(slot$range, wanted$range) &&
      !isTRUE(slot$multivalued) &&
      (is.null(wanted$identifier) || isTRUE(slot$identifier)) &&
      (is.null(wanted$required) || isTRUE(slot$required))
    if (!ok) {
      abort_schema_error(
        paste0(
          "The `graft_blob` table needs a string `id` primary key, a ",
          "required string `media_type`, and a required numeric ",
          "`size_bytes`; `",
          name,
          "` does not match."
        ),
        field = paste0(blob_class, ".", name),
        rule = "blob_contract"
      )
    }
  }
  invisible(manifest)
}

has_blob_contract <- function(store) {
  blob_class %in% names(store$schema$manifest$classes)
}

require_blob_contract <- function(store) {
  if (!has_blob_contract(store)) {
    abort_schema_error(
      "The store's contract has no `graft_blob` table.",
      rule = "blob_contract"
    )
  }
  invisible(store)
}

resolve_blob_path <- function(store_path) {
  if (
    identical(store_path, ":memory:") ||
      identical(store_path, "<caller-supplied>")
  ) {
    return(NULL)
  }
  extension <- tools::file_ext(store_path)
  stem <- if (nzchar(extension)) {
    tools::file_path_sans_ext(store_path)
  } else {
    store_path
  }
  paste0(stem, ".blobs")
}

blob_root <- function(store) {
  if (is.null(store$blob_path)) {
    store$blob_path <- tempfile("graft-blobs-")
  }
  store$blob_path
}

blob_file <- function(store, hex) {
  file.path(blob_root(store), substr(hex, 1L, 2L), hex)
}

blob_hex <- function(id) {
  substr(id, 8L, nchar(id))
}

blob_input_bytes <- function(x) {
  if (is.raw(x)) {
    return(x)
  }
  if (
    is.character(x) &&
      length(x) == 1L &&
      !is.na(x) &&
      file.exists(x) &&
      !dir.exists(x)
  ) {
    return(readBin(x, "raw", n = file.size(x)))
  }
  abort_validation_error(
    "`x` must be a raw vector or the path to one existing file.",
    field = "x",
    rule = "blob_input"
  )
}

validate_media_type <- function(media_type) {
  if (
    !is.character(media_type) ||
      length(media_type) != 1L ||
      is.na(media_type) ||
      !grepl("^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+", media_type)
  ) {
    abort_validation_error(
      "`media_type` must be one media type, such as `\"image/png\"`.",
      field = "media_type",
      rule = "media_type",
      observed_value = media_type
    )
  }
  media_type
}

validate_blob_id <- function(id) {
  if (
    !is.character(id) ||
      length(id) != 1L ||
      is.na(id) ||
      !grepl(blob_id_pattern, id)
  ) {
    abort_validation_error(
      "`id` must be a blob id of the form `sha256:<64 hex digits>`.",
      field = "id",
      rule = "blob_id",
      observed_value = id
    )
  }
  id
}

write_blob_bytes <- function(store, hex, bytes) {
  path <- blob_file(store, hex)
  if (file.exists(path)) {
    problem <- blob_bytes_problem(store, paste0("sha256:", hex), length(bytes))
    if (is.null(problem)) {
      return(invisible(path))
    }
    abort_blob_error(
      paste0(
        "A stored blob does not match its name; remove `",
        path,
        "` and stage it again."
      ),
      record_id = paste0("sha256:", hex),
      rule = problem$rule
    )
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  stage <- tempfile(".stage-", tmpdir = dirname(path))
  on.exit(unlink(stage, force = TRUE), add = TRUE)
  writeBin(bytes, stage)
  if (!file.rename(stage, path) && !file.exists(path)) {
    abort_blob_error(
      paste0("Could not write blob `", path, "`."),
      record_id = paste0("sha256:", hex),
      rule = "blob_write"
    )
  }
  invisible(path)
}

blob_bytes_problem <- function(store, id, expected_size) {
  path <- blob_file(store, blob_hex(id))
  if (!file.exists(path)) {
    return(list(
      rule = "blob_missing",
      message = paste0("The bytes for blob `", id, "` are missing.")
    ))
  }
  size <- file.size(path)
  if (!isTRUE(all.equal(as.double(size), as.double(expected_size)))) {
    return(list(
      rule = "blob_size",
      message = paste0(
        "Blob `",
        id,
        "` has ",
        size,
        " bytes, not the recorded ",
        format(expected_size, scientific = FALSE),
        "."
      )
    ))
  }
  observed <- digest::digest(path, algo = "sha256", file = TRUE)
  if (!identical(paste0("sha256:", observed), id)) {
    return(list(
      rule = "blob_digest",
      message = paste0("The bytes for blob `", id, "` do not match its digest.")
    ))
  }
  NULL
}

candidate_blob_issues <- function(store, records, changes) {
  if (!has_blob_contract(store)) {
    return(list())
  }
  issues <- list()
  rows <- records[[blob_class]]
  if (!is.null(rows) && nrow(rows) > 0L) {
    for (index in seq_len(nrow(rows))) {
      id <- rows$id[[index]]
      problem <- if (is.na(id) || !grepl(blob_id_pattern, id)) {
        list(
          rule = "blob_id",
          message = "A blob id must have the form `sha256:<64 hex digits>`."
        )
      } else {
        blob_bytes_problem(store, id, rows$size_bytes[[index]])
      }
      if (!is.null(problem)) {
        issues[[length(issues) + 1L]] <- new_plan_issue(
          record_class = blob_class,
          input_row = index,
          record_id = id,
          field = "id",
          rule = problem$rule,
          message = problem$message,
          condition_class = "graft_blob_error"
        )
      }
    }
  }
  changed <- which(changes$class == blob_class & changes$action == "update")
  for (index in changed) {
    issues[[length(issues) + 1L]] <- new_plan_issue(
      record_class = blob_class,
      input_row = changes$input_row[[index]],
      record_id = changes$record_id[[index]],
      field = "id",
      rule = "blob_immutable",
      message = "A committed blob cannot change; stage new bytes instead.",
      condition_class = "graft_blob_error"
    )
  }
  issues
}

verify_plan_blobs <- function(store, records, changes) {
  issues <- candidate_blob_issues(store, records, changes)
  if (length(issues) > 0L) {
    first <- issues[[1L]]
    abort_blob_error(
      paste0(
        "Blob bytes changed after planning: ",
        first$message
      ),
      record_id = first$record_id,
      rule = first$rule
    )
  }
  invisible(store)
}
