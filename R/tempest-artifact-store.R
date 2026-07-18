# Tempest integration boundaries

tempest_public_api <- function() {
  if (!requireNamespace("tempest", quietly = TRUE)) {
    return(NULL)
  }
  list(
    version = as.character(utils::packageVersion("tempest")),
    exports = sort(getNamespaceExports("tempest"))
  )
}

abort_tempest_dependency_error <- function(call = rlang::caller_env()) {
  graft_abort(
    "graft_tempest_dependency_error",
    c(
      "Tempest is required to construct a Tempest artifact-store adapter.",
      i = "Install Tempest, then call `tempest_artifact_store_graft()` again."
    ),
    package = "tempest",
    call = call
  )
}

abort_tempest_artifact_store_unsupported <- function(
  api,
  call = rlang::caller_env()
) {
  requirements <- c(
    "A versioned public encoder for an artifact and its deliverable specification.",
    "A public validated restore function for that durable envelope.",
    "A write callback that supplies the deliverable specification or a complete envelope."
  )
  graft_abort(
    "graft_tempest_artifact_store_unsupported",
    c(
      paste0(
        "Tempest ",
        api$version,
        " cannot support a durable Graft artifact-store adapter."
      ),
      i = paste0(
        "Its write callback supplies only a `TempestArtifact`; validated ",
        "restoration also requires the complete `TempestDeliverableSpec`."
      ),
      x = paste0(
        "The required envelope encoder and restore contract are not public."
      ),
      ">" = paste0(
        "Tempest must export a versioned artifact-and-deliverable envelope ",
        "encoder plus a validated restore function, or pass the deliverable ",
        "specification to the write callback."
      )
    ),
    tempest_version = api$version,
    tempest_exports = api$exports,
    upstream_requirements = requirements,
    call = call
  )
}

#' Create a Graft-backed Tempest artifact-store adapter
#'
#' The current Tempest artifact-store callback receives a typed artifact but
#' not the deliverable specification required for validated reconstruction.
#' Graft therefore refuses to construct an adapter until Tempest exposes a
#' complete, versioned public serialization contract. It does not use internal
#' Tempest helpers, fabricate a specification, or store opaque R
#' serialization.
#'
#' Use [kg_ingest_tempest_records()] for the supported multi-run knowledge
#' handoff.
#'
#' @param store An initialized, writable `kg_store`.
#'
#' @return This implementation does not return. It aborts with
#'   `graft_tempest_dependency_error` when Tempest is unavailable, or
#'   `graft_tempest_artifact_store_unsupported` because the current public
#'   Tempest API lacks the required durable contract.
#' @export
tempest_artifact_store_graft <- function(store) {
  validate_initialized_store_for_ingest(store, write = TRUE)
  api <- tempest_public_api()
  if (is.null(api)) {
    abort_tempest_dependency_error()
  }
  abort_tempest_artifact_store_unsupported(api)
}

#' Ingest records mapped from one Tempest run
#'
#' This is the durable Tempest-to-Graft knowledge handoff. Tempest maps its
#' domain objects to concrete Graft record data frames before calling this
#' function. The run identifier is both producer lineage and the default
#' idempotency key. A stage uses `<run_id>:<stage>`, allowing independently
#' replayable stage commits.
#'
#' This function is independent of Tempest's typed deliverable artifact-store
#' adapter.
#'
#' @param store An initialized, writable `kg_store`.
#' @param run_id One stable Tempest run identifier.
#' @param records A named list of mapped concrete-class data frames accepted by
#'   [kg_ingest()].
#' @param stage Optional stable stage identifier, such as `"search"` or
#'   `"synthesize"`.
#' @param producer_version Optional Tempest producer version.
#'
#' @return A `kg_ingest_result`. Replaying the same run and stage returns the
#'   original committed result with `replay = TRUE` and signals
#'   `graft_batch_replay`.
#' @export
kg_ingest_tempest_records <- function(
  store,
  run_id,
  records,
  stage = NULL,
  producer_version = NULL
) {
  run_id <- batch_scalar(run_id, "run_id", required = TRUE)
  stage <- batch_scalar(stage, "stage")
  producer_version <- batch_scalar(producer_version, "producer_version")
  idempotency_key <- if (is.na(stage)) {
    run_id
  } else {
    paste0(run_id, ":", stage)
  }
  stage_metadata <- if (is.na(stage)) NULL else stage
  batch <- kg_batch(
    producer = "tempest",
    producer_version = if (is.na(producer_version)) {
      NULL
    } else {
      producer_version
    },
    source_run_id = run_id,
    idempotency_key = idempotency_key,
    metadata = list(
      graft_tempest = list(
        run_id = run_id,
        stage = stage_metadata
      )
    )
  )
  kg_ingest(store, batch, records)
}
