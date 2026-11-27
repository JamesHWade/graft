# Shared validation predicates, normalizing checkers, and bounded file reads ---

ARTIFACT_STORE_MARKER <- charToRaw('{"format":"graft-artifacts","version":1}')

graft_is_whole_number <- function(x, min = 1, max = .Machine$integer.max) {
  is.numeric(x) &&
    length(x) == 1L &&
    !is.na(x) &&
    is.finite(x) &&
    x >= min &&
    x <= max &&
    x == floor(x)
}

graft_is_text <- function(x) {
  is.character(x) &&
    length(x) == 1L &&
    !is.na(x) &&
    validUTF8(enc2utf8(x)) &&
    nzchar(x) &&
    identical(trimws(x), x) &&
    nchar(enc2utf8(x), type = "bytes") <= 1024L &&
    !grepl("[[:cntrl:]]", x)
}

graft_is_path <- function(x) {
  is.character(x) &&
    length(x) == 1L &&
    !is.na(x) &&
    validUTF8(enc2utf8(x)) &&
    nzchar(x)
}

graft_is_digest <- function(x) {
  is.character(x) &&
    length(x) == 1L &&
    !is.na(x) &&
    grepl("^[0-9a-f]{64}$", x)
}

artifact_check_path <- function(
  path,
  class = "graft_artifact_error",
  call = rlang::caller_env()
) {
  if (!graft_is_path(path)) {
    graft_abort(
      class,
      "`path` must be a nonempty UTF-8 string.",
      call = call
    )
  }
}

artifact_check_text <- function(
  x,
  arg,
  class = "graft_artifact_error",
  call = rlang::caller_env()
) {
  if (rlang::is_string(x)) {
    attributes(x) <- NULL
    x <- enc2utf8(x)
  }
  if (!graft_is_text(x)) {
    graft_abort(
      class,
      paste0(
        "`",
        arg,
        "` must be a nonempty, unpadded string of at most 1024 UTF-8 bytes without control characters."
      ),
      call = call
    )
  }
  x
}

artifact_check_limit <- function(
  x,
  arg,
  min = 1,
  class = "graft_artifact_error",
  call = rlang::caller_env()
) {
  if (!graft_is_whole_number(x, min = min)) {
    kind <- if (min == 0) "non-negative" else "positive"
    graft_abort(
      class,
      paste0(
        "`",
        arg,
        "` must be a ",
        kind,
        " whole number no greater than the R integer limit."
      ),
      call = call
    )
  }
  invisible(NULL)
}

artifact_check_digest <- function(
  x,
  class = "graft_artifact_error",
  call = rlang::caller_env()
) {
  if (rlang::is_string(x)) {
    attributes(x) <- NULL
  }
  if (!graft_is_digest(x)) {
    graft_abort(
      class,
      "An artifact digest must contain 64 lowercase hexadecimal characters.",
      call = call
    )
  }
  x
}

graft_read_regular_file <- function(
  path,
  max_bytes,
  min_bytes = 0,
  class = "graft_artifact_error",
  missing_message = "Artifact file is missing or exceeds the byte bound.",
  read_message = "Could not read artifact bytes.",
  changed_message = "Artifact file changed during read.",
  call = rlang::caller_env()
) {
  info <- fs::file_info(path, fail = FALSE, follow = FALSE)
  size <- as.numeric(info$size)
  if (
    !identical(as.character(info$type), "file") ||
      is.na(size) ||
      size < min_bytes ||
      size > max_bytes
  ) {
    graft_abort(class, missing_message, call = call)
  }
  bytes <- tryCatch(
    readBin(path, "raw", n = size),
    error = function(e) graft_abort(class, read_message, call = call)
  )
  if (length(bytes) != size) {
    graft_abort(class, changed_message, call = call)
  }
  bytes
}
