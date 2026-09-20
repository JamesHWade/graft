# Public S7 values -----------------------------------------------------------

graft_value_abort <- function(message) {
  graft_abort("graft_value_error", message)
}

graft_value_text <- function(value, name) {
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !validUTF8(enc2utf8(value)) ||
      !nzchar(value) ||
      !identical(trimws(value), value) ||
      grepl("[[:cntrl:]]", value) ||
      nchar(enc2utf8(value), type = "bytes") > 1024L
  ) {
    graft_value_abort(paste0(
      "`",
      name,
      "` must be one nonempty, unpadded UTF-8 string without control",
      " characters and at most 1024 bytes."
    ))
  }
  NULL
}

graft_value_digest <- function(value, name, allow_null = FALSE) {
  if (allow_null && is.null(value)) {
    return(NULL)
  }
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !grepl("^[0-9a-f]{64}$", value)
  ) {
    graft_value_abort(paste0(
      "`",
      name,
      "` must be a 64-character lowercase SHA-256 digest",
      if (allow_null) " or NULL." else "."
    ))
  }
  NULL
}

graft_value_refs <- function(value, name) {
  if (!is.list(value) || is.object(value)) {
    graft_value_abort(paste0(
      "`",
      name,
      "` must be a list of ArtifactRef values."
    ))
  }
  for (item in value) {
    if (!S7::S7_inherits(item, ArtifactRef)) {
      graft_value_abort(paste0(
        "`",
        name,
        "` must contain only ArtifactRef values."
      ))
    }
  }
  NULL
}

graft_value_artifacts <- function(value, name) {
  if (!is.list(value) || is.object(value)) {
    graft_value_abort(paste0("`", name, "` must be a list of Artifact values."))
  }
  for (item in value) {
    if (!S7::S7_inherits(item, Artifact)) {
      graft_value_abort(paste0(
        "`",
        name,
        "` must contain only Artifact values."
      ))
    }
  }
  NULL
}

graft_value_data <- function(value) {
  if (is.raw(value)) {
    return(NULL)
  }
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !validUTF8(enc2utf8(value))
  ) {
    graft_value_abort("`data` must be raw bytes or one valid UTF-8 string.")
  }
  NULL
}

graft_value_sequence <- function(value) {
  if (
    !is.integer(value) ||
      length(value) != 1L ||
      is.na(value) ||
      value < 1L
  ) {
    graft_value_abort("`sequence` must be one positive integer.")
  }
  NULL
}

graft_value_action <- function(value) {
  graft_value_text(value, "action")
  if (!value %in% c("accept", "withdraw")) {
    graft_value_abort("`action` must be either \"accept\" or \"withdraw\".")
  }
  NULL
}

graft_value_status <- function(value) {
  graft_value_text(value, "status")
  if (!value %in% c("missing", "withdrawn", "accepted")) {
    graft_value_abort(
      "`status` must be \"missing\", \"withdrawn\", or \"accepted\"."
    )
  }
  NULL
}

graft_value_nullable_decision <- function(value, name) {
  if (is.null(value)) {
    return(NULL)
  }
  if (!S7::S7_inherits(value, Decision)) {
    graft_value_abort(paste0("`", name, "` must be a Decision or NULL."))
  }
  NULL
}

graft_value_nullable_selection <- function(value, name) {
  if (is.null(value)) {
    return(NULL)
  }
  if (!S7::S7_inherits(value, ArtifactSelection)) {
    graft_value_abort(paste0(
      "`",
      name,
      "` must be an ArtifactSelection or NULL."
    ))
  }
  NULL
}

#' An exact immutable artifact reference
#'
#' `ArtifactRef` identifies one logical artifact identity and one immutable
#' revision. It is a value descriptor; it does not grant access to the artifact.
#'
#' @param id Stable artifact identity.
#' @param revision Lowercase SHA-256 digest of the immutable revision metadata.
#' @export
ArtifactRef <- S7::new_class(
  "ArtifactRef",
  package = "graft",
  properties = list(
    id = S7::new_property(
      S7::class_character,
      validator = function(value) graft_value_text(value, "id")
    ),
    revision = S7::new_property(
      S7::class_character,
      validator = function(value) graft_value_digest(value, "revision")
    )
  )
)

#' Materialized immutable artifact content
#'
#' An `Artifact` contains exact bytes together with the media type and exact
#' dependency references recorded with those bytes. `data` is decoded text for
#' `text/*` media types and raw bytes for all other media types.
#'
#' @param ref Exact artifact reference.
#' @param bytes Exact retained bytes.
#' @param media_type Media type recorded for the artifact.
#' @param dependencies Exact dependency references.
#' @param data Decoded scalar text or raw bytes.
#' @export
Artifact <- S7::new_class(
  "Artifact",
  package = "graft",
  properties = list(
    ref = ArtifactRef,
    bytes = S7::class_raw,
    media_type = S7::new_property(
      S7::class_character,
      validator = function(value) graft_value_text(value, "media_type")
    ),
    dependencies = S7::new_property(
      S7::class_any,
      validator = function(value) graft_value_refs(value, "dependencies")
    ),
    data = S7::new_property(
      S7::class_any,
      validator = graft_value_data
    )
  )
)

#' A verified artifact dependency selection
#'
#' An `ArtifactSelection` records one exact selection digest, its roots, and
#' the complete verified dependency closure. It does not grant approval or
#' access to the selected artifacts.
#'
#' @param id Exact selection digest.
#' @param roots Exact root references in caller order.
#' @param artifacts Complete breadth-first dependency closure.
#' @export
ArtifactSelection <- S7::new_class(
  "ArtifactSelection",
  package = "graft",
  properties = list(
    id = S7::new_property(
      S7::class_character,
      validator = function(value) graft_value_digest(value, "id")
    ),
    roots = S7::new_property(
      S7::class_any,
      validator = function(value) graft_value_refs(value, "roots")
    ),
    artifacts = S7::new_property(
      S7::class_any,
      validator = function(value) graft_value_refs(value, "artifacts")
    )
  )
)

#' A host decision recorded in an artifact stream
#'
#' `Decision` is a journal value describing one acceptance or withdrawal. Its
#' `selection` property is the exact selection digest, not a materialized
#' selection. It is a descriptor and does not authenticate its actor or grant
#' current consultation access.
#'
#' @param id Decision digest.
#' @param sequence Chronological sequence number within the stream.
#' @param stream Host-chosen decision stream.
#' @param key Stable host idempotency key.
#' @param previous Exact predecessor decision digest, or `NULL` for the first
#'   record.
#' @param action Either `"accept"` or `"withdraw"`.
#' @param selection Exact selection digest named by the decision.
#' @param actor Host-supplied actor identity.
#' @param reason Host-supplied review or withdrawal reason.
#' @param purpose Host-supplied consultation purpose.
#' @export
Decision <- S7::new_class(
  "Decision",
  package = "graft",
  properties = list(
    id = S7::new_property(
      S7::class_character,
      validator = function(value) graft_value_digest(value, "id")
    ),
    sequence = S7::new_property(
      S7::class_integer,
      validator = graft_value_sequence
    ),
    stream = S7::new_property(
      S7::class_character,
      validator = function(value) graft_value_text(value, "stream")
    ),
    key = S7::new_property(
      S7::class_character,
      validator = function(value) graft_value_text(value, "key")
    ),
    previous = S7::new_property(
      S7::class_any,
      validator = function(value) graft_value_digest(value, "previous", TRUE)
    ),
    action = S7::new_property(
      S7::class_character,
      validator = graft_value_action
    ),
    selection = S7::new_property(
      S7::class_character,
      validator = function(value) graft_value_digest(value, "selection")
    ),
    actor = S7::new_property(
      S7::class_character,
      validator = function(value) graft_value_text(value, "actor")
    ),
    reason = S7::new_property(
      S7::class_character,
      validator = function(value) graft_value_text(value, "reason")
    ),
    purpose = S7::new_property(
      S7::class_character,
      validator = function(value) graft_value_text(value, "purpose")
    )
  )
)

#' The result of a current reviewed-artifact lookup
#'
#' `Recall` reports a point-in-time `status` of `missing`, `withdrawn`, or
#' `accepted`. Missing and withdrawn results contain no materialized payload.
#' Accepted results contain the current verified decision, selection, roots,
#' and complete materialized dependency closure.
#'
#' @param status Lookup status.
#' @param decision Current verified decision, or `NULL` when missing.
#' @param selection Current verified selection, or `NULL` when missing or
#'   withdrawn.
#' @param roots Materialized root artifacts for an accepted recall.
#' @param artifacts Complete materialized closure for an accepted recall.
#' @export
Recall <- S7::new_class(
  "Recall",
  package = "graft",
  properties = list(
    status = S7::new_property(
      S7::class_character,
      validator = graft_value_status
    ),
    decision = S7::new_property(
      S7::class_any,
      validator = function(value) {
        graft_value_nullable_decision(value, "decision")
      }
    ),
    selection = S7::new_property(
      S7::class_any,
      validator = function(value) {
        graft_value_nullable_selection(value, "selection")
      }
    ),
    roots = S7::new_property(
      S7::class_any,
      validator = function(value) graft_value_artifacts(value, "roots")
    ),
    artifacts = S7::new_property(
      S7::class_any,
      validator = function(value) graft_value_artifacts(value, "artifacts")
    )
  )
)

S7::method(print, ArtifactRef) <- function(x, ...) {
  cat("<ArtifactRef ", x@id, "@", x@revision, ">\n", sep = "")
  invisible(x)
}

S7::method(print, Artifact) <- function(x, ...) {
  cat(
    "<Artifact ",
    x@ref@id,
    "@",
    x@ref@revision,
    " media_type=",
    x@media_type,
    " bytes=",
    length(x@bytes),
    ">\n",
    sep = ""
  )
  invisible(x)
}

S7::method(print, ArtifactSelection) <- function(x, ...) {
  cat(
    "<ArtifactSelection ",
    x@id,
    " roots=",
    length(x@roots),
    " artifacts=",
    length(x@artifacts),
    ">\n",
    sep = ""
  )
  invisible(x)
}

S7::method(print, Decision) <- function(x, ...) {
  cat(
    "<Decision ",
    x@action,
    " stream=",
    x@stream,
    " sequence=",
    x@sequence,
    " id=",
    x@id,
    ">\n",
    sep = ""
  )
  invisible(x)
}

S7::method(print, Recall) <- function(x, ...) {
  cat(
    "<Recall status=",
    x@status,
    " roots=",
    length(x@roots),
    " artifacts=",
    length(x@artifacts),
    ">\n",
    sep = ""
  )
  invisible(x)
}

artifact_ref_value <- function(record) {
  if (S7::S7_inherits(record, ArtifactRef)) {
    return(record)
  }
  if (!is.list(record) || is.object(record)) {
    graft_value_abort("An artifact reference record must be a plain list.")
  }
  record <- tryCatch(
    artifact_check_ref(record),
    graft_artifact_error = function(e) graft_value_abort(conditionMessage(e))
  )
  ArtifactRef(id = record$id, revision = record$revision)
}

artifact_ref_record <- function(ref) {
  if (!S7::S7_inherits(ref, ArtifactRef)) {
    graft_value_abort("`ref` must be an ArtifactRef value.")
  }
  record <- list(id = ref@id, revision = ref@revision)
  tryCatch(
    artifact_check_ref(record),
    graft_artifact_error = function(e) graft_value_abort(conditionMessage(e))
  )
}

artifact_refs_records <- function(refs) {
  if (S7::S7_inherits(refs, ArtifactRef)) {
    return(list(artifact_ref_record(refs)))
  }
  if (!is.list(refs) || is.object(refs)) {
    graft_value_abort(
      "Expected one ArtifactRef or a list of ArtifactRef values."
    )
  }
  unname(lapply(refs, artifact_ref_record))
}

artifact_selection_value <- function(record) {
  if (S7::S7_inherits(record, ArtifactSelection)) {
    return(record)
  }
  if (
    !is.list(record) ||
      is.object(record) ||
      !identical(names(record), c("id", "roots", "artifacts"))
  ) {
    graft_value_abort(
      "An artifact selection record must contain id, roots, and artifacts."
    )
  }
  id <- tryCatch(
    artifact_check_digest(record$id),
    graft_artifact_error = function(e) graft_value_abort(conditionMessage(e))
  )
  roots <- unname(lapply(record$roots, artifact_ref_value))
  artifacts <- unname(lapply(record$artifacts, artifact_ref_value))
  ArtifactSelection(id = id, roots = roots, artifacts = artifacts)
}

artifact_selection_record <- function(selection) {
  if (!S7::S7_inherits(selection, ArtifactSelection)) {
    graft_value_abort("`selection` must be an ArtifactSelection value.")
  }
  list(
    id = tryCatch(
      artifact_check_digest(selection@id),
      graft_artifact_error = function(e) graft_value_abort(conditionMessage(e))
    ),
    roots = artifact_refs_records(selection@roots),
    artifacts = artifact_refs_records(selection@artifacts)
  )
}

artifact_decision_value <- function(record) {
  if (S7::S7_inherits(record, Decision)) {
    return(record)
  }
  if (
    !is.list(record) ||
      is.object(record) ||
      !identical(
        names(record),
        c(
          "id",
          "sequence",
          "stream",
          "key",
          "previous",
          "action",
          "selection",
          "actor",
          "reason",
          "purpose"
        )
      )
  ) {
    graft_value_abort("A decision record has an unsupported shape.")
  }
  id <- tryCatch(
    artifact_check_digest(record$id),
    graft_artifact_error = function(e) graft_value_abort(conditionMessage(e))
  )
  previous <- record$previous
  if (!is.null(previous)) {
    previous <- tryCatch(
      artifact_check_digest(previous),
      graft_artifact_error = function(e) graft_value_abort(conditionMessage(e))
    )
  }
  selection <- tryCatch(
    artifact_check_digest(record$selection),
    graft_artifact_error = function(e) graft_value_abort(conditionMessage(e))
  )
  sequence <- record$sequence
  if (
    !is.numeric(sequence) ||
      length(sequence) != 1L ||
      is.na(sequence) ||
      !is.finite(sequence) ||
      sequence < 1 ||
      sequence != floor(sequence) ||
      sequence > .Machine$integer.max
  ) {
    graft_value_abort("`sequence` must be one positive integer.")
  }
  Decision(
    id = id,
    sequence = as.integer(sequence),
    stream = artifact_check_text(record$stream, "stream"),
    key = artifact_check_text(record$key, "key"),
    previous = previous,
    action = artifact_check_text(record$action, "action"),
    selection = selection,
    actor = artifact_check_text(record$actor, "actor"),
    reason = artifact_check_text(record$reason, "reason"),
    purpose = artifact_check_text(record$purpose, "purpose")
  )
}

artifact_text_data <- function(bytes, media_type) {
  if (!startsWith(tolower(media_type), "text/")) {
    return(bytes)
  }
  if (any(bytes == as.raw(0))) {
    graft_abort(
      "graft_artifact_decode_error",
      "Text artifact bytes contain an embedded NUL character."
    )
  }
  text <- tryCatch(
    rawToChar(bytes),
    error = function(e) {
      graft_abort(
        "graft_artifact_decode_error",
        "Text artifact bytes could not be decoded as UTF-8."
      )
    }
  )
  if (!validUTF8(text)) {
    graft_abort(
      "graft_artifact_decode_error",
      "Text artifact bytes are not valid UTF-8."
    )
  }
  Encoding(text) <- "UTF-8"
  text
}

artifact_value <- function(record) {
  if (S7::S7_inherits(record, Artifact)) {
    return(record)
  }
  if (
    !is.list(record) ||
      is.object(record) ||
      !identical(names(record), c("ref", "metadata", "bytes"))
  ) {
    graft_value_abort("An artifact record has an unsupported shape.")
  }
  metadata <- record$metadata
  if (
    !is.list(metadata) ||
      !identical(
        names(metadata),
        c("format", "id", "payload", "size", "media_type", "dependencies")
      )
  ) {
    graft_value_abort("An artifact record has unsupported metadata.")
  }
  ref <- artifact_ref_value(record$ref)
  bytes <- record$bytes
  if (!is.raw(bytes)) {
    graft_value_abort("An artifact record must contain raw bytes.")
  }
  tryCatch(
    artifact_check_metadata(metadata),
    graft_artifact_error = function(e) graft_value_abort(conditionMessage(e))
  )
  if (
    !identical(metadata$id, ref@id) ||
      as.numeric(metadata$size) != length(bytes) ||
      !identical(artifact_sha(bytes), metadata$payload)
  ) {
    graft_value_abort(
      "An artifact record failed identity or byte verification."
    )
  }
  Artifact(
    ref = ref,
    bytes = bytes,
    media_type = metadata$media_type,
    dependencies = lapply(metadata$dependencies, artifact_ref_value),
    data = artifact_text_data(bytes, metadata$media_type)
  )
}
