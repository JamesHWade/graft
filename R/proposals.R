#' Derive a structured proposal type from the accepted dictionary
#'
#' `graft_proposal_type()` returns a public ellmer type for an object whose
#' properties are table names and whose values are arrays of complete candidate
#' records. Use `chat$chat_structured(..., type = type, convert = FALSE)` to retain
#' raw output for [graft_proposal_plan()]. The type can also be supplied to a
#' dsprrr signature's `output_type` argument.
#'
#' Every selected property is required in the output object. Optional columns
#' accept JSON null; required columns and list elements do not. Primary keys and
#' foreign keys are strings. Foreign-key existence, cross-record constraints,
#' and accepted state are checked by planning, not by a model's output schema.
#' Restricted columns are excluded. Tables with required restricted columns are
#' rejected: those records require a trusted host's ordinary [graft_plan()] path.
#' Only schema-derived type information is sent to the model, with no examples,
#' source paths, or free-form dictionary metadata.
#'
#' @param source An initialized `GraftStore` or immutable `GraftView` with a
#'   data-dict contract. A view freezes the type's contract; planning always
#'   validates against the destination store's active contract.
#' @param tables Optional character vector of dictionary table names.
#' @param fields Optional named list of column-name vectors, keyed by selected
#'   table. Unspecified tables include every public column. Selections must
#'   include all required columns and may not include restricted columns.
#' @param max_rows Maximum records per table, from 1 to 1,000.
#' @return An `ellmer::Type` object usable by `chat_structured()` or dsprrr.
#' @export
graft_proposal_type <- function(
  source,
  tables = NULL,
  fields = NULL,
  max_rows = 100L
) {
  check_graft_tools_dependency()
  rlang::check_number_whole(max_rows, min = 1, max = 1000)
  context <- graft_tool_context(source)
  manifest <- proposal_manifest(context$store)
  selection <- proposal_selection(manifest, tables, fields)
  properties <- lapply(names(selection), function(table) {
    slots <- manifest$classes[[table]]$slots[selection[[table]]]
    columns <- lapply(slots, proposal_column_schema, manifest = manifest)
    list(
      type = "array",
      maxItems = as.integer(max_rows),
      items = list(
        type = "object",
        properties = columns,
        required = as.list(names(columns)),
        additionalProperties = FALSE
      )
    )
  })
  names(properties) <- names(selection)
  ellmer::type_from_schema(
    text = canonical_json(list(
      type = "object",
      properties = properties,
      required = as.list(names(properties)),
      additionalProperties = FALSE
    ))
  )
}

#' Turn raw structured proposals into a reviewable plan
#'
#' `graft_proposal_plan()` checks the raw object shape, preserves each row and
#' value in list-columns, and delegates acceptance validation to [graft_plan()].
#' It never commits, calls a provider, or requires ellmer. Supply the unconverted
#' result of `chat_structured(..., convert = FALSE)`; converted data frames are
#' rejected so upstream conversion cannot hide unknown fields or malformed rows.
#'
#' Malformed objects, unknown or restricted fields, and incompatible JSON value
#' types raise a `graft_validation_error`. Missing required values, invalid enum
#' values, and unknown references are reported in the returned plan's `@issues`.
#' These are complete candidate records, not patches: omitted optional values
#' are missing values under ordinary planning semantics. The host retains review,
#' provenance, idempotency, credentials, and the decision to [graft_commit()].
#' Retain the accepted plan to retry its commit. Replanning after acceptance
#' creates a different plan and cannot reuse an already committed replay key.
#'
#' @param store An initialized `GraftStore` with a data-dict contract.
#' @param proposal A named list of table arrays, each an unnamed list of named
#'   record objects. JSON arrays must remain lists, including primitive lists.
#' @param provenance A [graft_provenance()] object with explicit idempotency.
#' @param max_rows Maximum records per table, from 1 to 1,000. Set this to the
#'   same value used for [graft_proposal_type()].
#' @return A `GraftCommitPlan` from [graft_plan()], without changing accepted data.
#' @export
graft_proposal_plan <- function(store, proposal, provenance, max_rows = 100L) {
  rlang::check_number_whole(max_rows, min = 1, max = 1000)
  backend <- as_graft_store_internal(store, "store")
  validate_initialized_store(backend, write = FALSE, refresh = TRUE)
  manifest <- proposal_manifest(store)
  provenance <- as_graft_provenance(provenance)
  if (is.na(provenance@idempotency_key)) {
    proposal_error(
      "provenance",
      "Structured proposals require an explicit idempotency key."
    )
  }
  proposal_check_object(proposal, "proposal")
  selection <- proposal_selection(manifest, names(proposal), NULL)
  frames <- lapply(names(proposal), function(table) {
    rows <- proposal[[table]]
    if (
      !is.list(rows) ||
        is.object(rows) ||
        !is.null(names(rows)) ||
        length(rows) > max_rows
    ) {
      proposal_error(table, "Expected a bounded JSON array of record objects.")
    }
    slots <- manifest$classes[[table]]$slots
    for (index in seq_along(rows)) {
      row <- rows[[index]]
      path <- paste0(table, "[", index, "]")
      proposal_check_object(row, path)
      if (!all(names(row) %in% selection[[table]])) {
        proposal_error(
          path,
          "Proposal contains an unknown or restricted column."
        )
      }
      for (field in names(row)) {
        rows[[index]][field] <- list(proposal_cell(
          row[[field]],
          slots[[field]],
          paste0(path, ".", field)
        ))
      }
    }
    fields <- unique(unlist(lapply(rows, names), use.names = FALSE))
    fields <- selection[[table]][selection[[table]] %in% fields]
    if (length(rows) == 0L) {
      fields <- selection[[table]]
    }
    columns <- lapply(fields, function(field) {
      I(lapply(rows, \(row) row[[field]]))
    })
    names(columns) <- fields
    as.data.frame(columns, check.names = FALSE, optional = TRUE)
  })
  names(frames) <- names(proposal)
  graft_plan(store, frames, provenance)
}

proposal_manifest <- function(source) {
  backend <- as_graft_read_store_internal(source, "source")
  validate_retrieval_store(backend)
  manifest <- backend$schema$manifest
  if (is.null(manifest$dictionary)) {
    proposal_error(
      "source",
      "Structured proposals require a data-dict contract."
    )
  }
  manifest
}

proposal_selection <- function(manifest, tables, fields) {
  public <- dictionary_public_fields(manifest)
  if (is.null(tables)) {
    tables <- names(public)
  }
  if (
    !is.character(tables) ||
      !length(tables) ||
      anyNA(tables) ||
      anyDuplicated(tables) ||
      !all(tables %in% names(public))
  ) {
    proposal_error("tables", "Select unique public dictionary tables.")
  }
  if (!is.null(fields)) {
    proposal_check_object(fields, "fields")
    if (!all(names(fields) %in% tables)) {
      proposal_error(
        "fields",
        "Field selections must belong to selected tables."
      )
    }
  }
  result <- lapply(tables, function(table) {
    slots <- manifest$classes[[table]]$slots
    required <- names(Filter(\(slot) isTRUE(slot$required), slots))
    selected <- fields[[table]]
    if (is.null(selected)) {
      selected <- public[[table]]
    }
    if (
      !is.character(selected) ||
        anyNA(selected) ||
        anyDuplicated(selected) ||
        !all(selected %in% public[[table]]) ||
        !all(required %in% selected)
    ) {
      proposal_error(
        "fields",
        "Include every required column and select only public columns."
      )
    }
    public[[table]][public[[table]] %in% selected]
  })
  stats::setNames(result, tables)
}

proposal_column_schema <- function(slot, manifest) {
  type <- proposal_json_type(slot)
  value <- list(type = type)
  if (identical(type, "string")) {
    value$minLength <- 1L
  }
  if (!is.null(slot$enum)) {
    value$enum <- lapply(
      manifest$enums[[slot$enum]]$permissible_values,
      `[[`,
      "value"
    )
  }
  if (identical(slot$duckdb_type, "DATE")) {
    value$format <- "date"
  }
  if (identical(slot$duckdb_type, "TIMESTAMP")) {
    value$description <- if (identical(slot$datetime_format, "local_utc")) {
      "UTC date-time without an offset, e.g. 2026-01-01T12:00:00."
    } else {
      "RFC 3339 date-time with an explicit offset."
    }
  }
  if (isTRUE(slot$object_reference)) {
    value$description <- paste0(
      "An existing or co-proposed ",
      slot$range,
      " primary id."
    )
  }
  if (isTRUE(slot$multivalued)) {
    value <- list(type = "array", items = value)
    if (isTRUE(slot$required)) value$minItems <- 1L
  }
  if (!isTRUE(slot$required)) {
    value <- list(anyOf = list(value, list(type = "null")))
  }
  value
}

proposal_json_type <- function(slot) {
  type <- switch(
    slot$duckdb_type,
    VARCHAR = "string",
    DATE = "string",
    TIMESTAMP = "string",
    DOUBLE = "number",
    BOOLEAN = "boolean",
    NULL
  )
  if (is.null(type)) {
    proposal_error(
      "type",
      "This contract type is not supported for structured proposals."
    )
  }
  type
}

proposal_cell <- function(value, slot, path) {
  if (is.null(value)) {
    return(NULL)
  }
  if (isTRUE(slot$multivalued)) {
    if (!is.list(value) || is.object(value) || !is.null(names(value))) {
      proposal_error(path, "Expected a JSON array or null.")
    }
    values <- value
  } else {
    values <- list(value)
  }
  type <- proposal_json_type(slot)
  valid <- vapply(
    values,
    function(value) {
      length(value) == 1L &&
        !is.object(value) &&
        !is.na(value) &&
        switch(
          type,
          string = is.character(value),
          number = is.numeric(value) && is.finite(value),
          boolean = is.logical(value)
        )
    },
    logical(1)
  )
  if (!all(valid)) {
    proposal_error(
      path,
      "Expected non-null scalar values of the declared JSON type."
    )
  }
  if (isTRUE(slot$multivalued)) unlist(values, use.names = FALSE) else value
}

proposal_check_object <- function(value, path) {
  if (
    !is.list(value) ||
      is.object(value) ||
      !length(value) ||
      is.null(names(value)) ||
      anyNA(names(value)) ||
      !all(nzchar(names(value))) ||
      anyDuplicated(names(value))
  ) {
    proposal_error(path, "Expected a non-empty JSON object with unique names.")
  }
}

proposal_error <- function(field, message) {
  abort_validation_error(message, field = field, rule = "proposal_shape")
}
