#' Abstract artifact store
#'
#' `ArtifactStore` is the common S7 type for bounded local and PostgreSQL
#' artifact stores. It cannot be instantiated directly.
#'
#' @param max_bytes Maximum payload bytes for one artifact and the complete
#'   dependency set it references.
#' @param max_revision_bytes Maximum encoded revision metadata bytes.
#' @export
ArtifactStore <- S7::new_class(
  "ArtifactStore",
  package = "graft",
  abstract = TRUE,
  properties = list(
    max_bytes = S7::new_property(
      S7::class_numeric,
      validator = function(value) {
        if (!artifact_store_valid_limit(value)) {
          "must be a positive whole number no greater than the R integer limit"
        }
      }
    ),
    max_revision_bytes = S7::new_property(
      S7::class_numeric,
      validator = function(value) {
        if (!artifact_store_valid_limit(value)) {
          "must be a positive whole number no greater than the R integer limit"
        }
      }
    )
  )
)

#' Local artifact store
#'
#' @param path Normalized local store directory.
#' @param max_bytes Maximum payload bytes for one artifact and the complete
#'   dependency set it references.
#' @param max_revision_bytes Maximum encoded revision metadata bytes.
#' @export
LocalArtifactStore <- S7::new_class(
  "LocalArtifactStore",
  package = "graft",
  parent = ArtifactStore,
  properties = list(
    path = S7::new_property(
      S7::class_character,
      validator = function(value) {
        if (!artifact_store_valid_path(value)) {
          "must be a nonempty UTF-8 filesystem path"
        }
      }
    )
  )
)

#' PostgreSQL artifact store
#'
#' @param connection An open transaction-scoped PostgreSQL connection.
#' @param scope Host-selected scope key.
#' @param max_bytes Maximum payload bytes for one artifact and the complete
#'   dependency set it references.
#' @param max_revision_bytes Maximum encoded revision metadata bytes.
#' @export
PostgresArtifactStore <- S7::new_class(
  "PostgresArtifactStore",
  package = "graft",
  parent = ArtifactStore,
  properties = list(
    connection = S7::new_property(
      S7::class_any,
      validator = function(value) {
        if (!artifact_store_valid_connection(value)) {
          "must be an open RPostgres connection"
        }
      }
    ),
    scope = S7::new_property(
      S7::class_character,
      validator = function(value) {
        if (!artifact_store_valid_text(value)) {
          "must be a nonempty UTF-8 string"
        }
      }
    )
  )
)

artifact_store_valid_limit <- function(value) {
  is.numeric(value) &&
    length(value) == 1L &&
    !is.na(value) &&
    is.finite(value) &&
    value >= 1 &&
    value <= .Machine$integer.max &&
    value == floor(value)
}

artifact_store_valid_text <- function(value) {
  is.character(value) &&
    length(value) == 1L &&
    !is.na(value) &&
    validUTF8(enc2utf8(value)) &&
    nzchar(value) &&
    identical(trimws(value), value) &&
    nchar(enc2utf8(value), type = "bytes") <= 1024 &&
    !grepl("[[:cntrl:]]", value)
}

artifact_store_valid_path <- function(value) {
  is.character(value) &&
    length(value) == 1L &&
    !is.na(value) &&
    validUTF8(enc2utf8(value)) &&
    nzchar(value)
}

artifact_store_valid_connection <- function(value) {
  inherits(value, "PqConnection") &&
    requireNamespace("DBI", quietly = TRUE) &&
    isTRUE(tryCatch(DBI::dbIsValid(value), error = function(...) FALSE))
}

artifact_storage_read <- S7::new_generic("artifact_storage_read", "store")
artifact_storage_put <- S7::new_generic("artifact_storage_put", "store")
artifact_decision_entries <- S7::new_generic(
  "artifact_decision_entries",
  "store"
)
artifact_decision_streams <- S7::new_generic(
  "artifact_decision_streams",
  "store"
)
