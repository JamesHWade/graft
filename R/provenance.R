GraftProvenance <- S7::new_class(
  "GraftProvenance",
  package = "graft",
  properties = list(
    producer = S7::new_property(
      S7::class_character,
      getter = \(self) provenance_data(self)$producer
    ),
    version = S7::new_property(
      S7::class_character,
      getter = \(self) provenance_data(self)$version
    ),
    run_id = S7::new_property(
      S7::class_character,
      getter = \(self) provenance_data(self)$run_id
    ),
    idempotency_key = S7::new_property(
      S7::class_character,
      getter = \(self) provenance_data(self)$idempotency_key
    ),
    metadata = S7::new_property(
      S7::class_list,
      getter = \(self) provenance_data(self)$metadata
    )
  ),
  constructor = function(data) {
    S7::new_object(S7::S7_object(), .data = data)
  },
  validator = function(self) {
    data <- provenance_data(self)
    required <- c(
      "producer",
      "version",
      "run_id",
      "idempotency_key",
      "metadata"
    )
    if (!identical(names(data), required)) {
      return("internal provenance fields are invalid")
    }
    if (
      length(self@producer) != 1L ||
        is.na(self@producer) ||
        !nzchar(self@producer)
    ) {
      return("@producer must be one non-empty string")
    }
    optional <- c(self@version, self@run_id, self@idempotency_key)
    if (length(optional) != 3L || any(!is.na(optional) & !nzchar(optional))) {
      return("optional provenance strings must be non-empty or missing")
    }
    if (!is.list(self@metadata) || is.data.frame(self@metadata)) {
      return("@metadata must be a list")
    }
    metadata_error <- tryCatch(
      {
        canonical_json(self@metadata)
        NULL
      },
      error = conditionMessage
    )
    if (!is.null(metadata_error)) {
      return("@metadata must be JSON serializable")
    }
    NULL
  }
)

#' Describe the provenance of a candidate knowledge change
#'
#' Provenance identifies the producer and optional upstream run that supplied a
#' candidate change. The producer and idempotency key form the replay boundary
#' when a reviewed plan is committed.
#'
#' @param producer One non-empty producer name.
#' @param version Optional producer version.
#' @param run_id Optional producer-side run identifier.
#' @param idempotency_key Optional key identifying a replay for this producer.
#' @param metadata A named JSON-serializable metadata list.
#'
#' @return An immutable `GraftProvenance` S7 object.
#' @export
graft_provenance <- function(
  producer,
  version = NULL,
  run_id = NULL,
  idempotency_key = NULL,
  metadata = list()
) {
  producer <- provenance_required_string(producer, "producer")
  version <- graft_optional_string(version, "version")
  run_id <- graft_optional_string(run_id, "run_id")
  idempotency_key <- graft_optional_string(
    idempotency_key,
    "idempotency_key"
  )
  if (!is.list(metadata) || is.data.frame(metadata)) {
    abort_validation_error(
      "`metadata` must be a JSON-serializable list.",
      field = "metadata",
      rule = "list",
      observed_value = metadata
    )
  }
  tryCatch(
    canonical_json(metadata),
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
  GraftProvenance(list(
    producer = producer,
    version = version,
    run_id = run_id,
    idempotency_key = idempotency_key,
    metadata = metadata
  ))
}

provenance_required_string <- function(x, field) {
  if (
    is.character(x) &&
      length(x) == 1L &&
      !is.na(x) &&
      nzchar(trimws(x))
  ) {
    return(trimws(x))
  }
  abort_validation_error(
    paste0("`", field, "` must be one non-empty string."),
    field = field,
    rule = "scalar_character",
    observed_value = x
  )
}

provenance_data <- function(x) {
  attr(x, ".data", exact = TRUE)
}

is_graft_provenance <- function(x) {
  S7::S7_inherits(x, GraftProvenance)
}

as_graft_provenance <- function(
  x,
  arg = rlang::caller_arg(x)
) {
  if (!is_graft_provenance(x)) {
    abort_validation_error(
      paste0("`", arg, "` must be a GraftProvenance object."),
      field = arg,
      rule = "graft_provenance",
      observed_value = x
    )
  }
  validation_error <- tryCatch(
    {
      S7::validate(x)
      NULL
    },
    error = \(error) error
  )
  if (!is.null(validation_error)) {
    abort_validation_error(
      paste0(
        "`",
        arg,
        "` is an invalid GraftProvenance object; create a new one."
      ),
      field = arg,
      rule = "graft_provenance_valid",
      observed_value = x,
      parent = validation_error
    )
  }
  x
}

commit_batch_from_provenance <- function(provenance, batch_id) {
  provenance <- as_graft_provenance(provenance, "provenance")
  new_commit_batch(
    batch_id = batch_id,
    producer = provenance@producer,
    producer_version = provenance@version,
    source_run_id = provenance@run_id,
    idempotency_key = provenance@idempotency_key,
    metadata = provenance@metadata
  )
}
