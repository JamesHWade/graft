#' Describe one atomic ingestion batch
#'
#' A batch records producer provenance and supplies the idempotency boundary for
#' [kg_ingest()]. Its identifier is minted once and remains stable for the life
#' of the object.
#'
#' @param producer One non-empty producer name.
#' @param producer_version Optional producer version.
#' @param source_run_id Optional producer-side run identifier.
#' @param idempotency_key Optional key that identifies a replay for this
#'   producer.
#' @param metadata A list of JSON-serializable batch metadata.
#'
#' @return A `kg_batch` object.
#' @export
kg_batch <- function(
  producer,
  producer_version = NULL,
  source_run_id = NULL,
  idempotency_key = NULL,
  metadata = list()
) {
  producer <- batch_scalar(producer, "producer", required = TRUE)
  producer_version <- batch_scalar(producer_version, "producer_version")
  source_run_id <- batch_scalar(source_run_id, "source_run_id")
  idempotency_key <- batch_scalar(idempotency_key, "idempotency_key")
  if (!is.list(metadata) || is.data.frame(metadata)) {
    abort_validation_error(
      "`metadata` must be a JSON-serializable list.",
      field = "metadata",
      rule = "list",
      observed_value = metadata
    )
  }
  tryCatch(
    jsonlite::toJSON(metadata, auto_unbox = TRUE, null = "null"),
    error = function(error) {
      abort_validation_error(
        paste0(
          "`metadata` must be JSON serializable: ",
          conditionMessage(error)
        ),
        field = "metadata",
        rule = "json_serializable",
        observed_value = metadata,
        parent = error
      )
    }
  )
  new_kg_batch(
    batch_id = new_graft_id(),
    producer = producer,
    producer_version = producer_version,
    source_run_id = source_run_id,
    idempotency_key = idempotency_key,
    metadata = metadata
  )
}

batch_scalar <- function(x, field, required = FALSE) {
  if (is.null(x)) {
    if (!required) {
      return(NA_character_)
    }
  } else if (
    is.character(x) &&
      length(x) == 1L &&
      !is.na(x) &&
      nzchar(trimws(x))
  ) {
    return(trimws(x))
  }
  qualifier <- if (required) {
    "one non-empty string"
  } else {
    "one non-empty string or `NULL`"
  }
  abort_validation_error(
    paste0("`", field, "` must be ", qualifier, "."),
    field = field,
    rule = "scalar_character",
    observed_value = x
  )
}
