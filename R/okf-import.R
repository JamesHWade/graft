# Open Knowledge Format proposal import

#' Review edited open knowledge as a commit plan
#'
#' `graft_review()` reads and validates an edited managed Open Knowledge Format
#' bundle without changing accepted knowledge. It returns the same immutable
#' plan type as [graft_plan()], bound to the exact bundle and accepted batch
#' observed during review. Call [graft_commit()] after approval, then synchronize
#' the working tree explicitly with [graft_sync()].
#'
#' @param store An initialized `GraftStore`.
#' @param path Optional edited bundle directory. The default uses the managed
#'   OKF directory.
#' @param provenance A [graft_provenance()] object describing the reviewer or
#'   host policy proposing the change.
#'
#' @return An immutable `GraftCommitPlan` S7 object.
#' @export
graft_review <- function(store, path = NULL, provenance) {
  store <- as_graft_store_internal(store, "store")
  proposal <- kg_plan_okf_import(store, path = path)
  graft_plan_records(
    store = store,
    records = proposal$records,
    provenance = provenance,
    source = "okf",
    source_preconditions = list(
      path = proposal$path,
      base_batch_id = proposal$base_batch_id,
      bundle_digest = proposal$proposed_bundle_digest
    )
  )
}

#' Plan changes from an edited Open Knowledge Format working tree
#'
#' Planning reads the editable `graft.record` mappings in a complete managed
#' bundle through a stable filesystem snapshot, compares them with current
#' accepted revisions, and validates proposed inserts and updates against the
#' active LinkML-derived manifest. It does not mutate the store. Removing concept
#' files is intentionally unsupported.
#'
#' The resulting plan is bound to the store identity, exact accepted batch,
#' active schema, and edited bundle digest. This makes it suitable for an
#' explicit human or host-policy approval step.
#'
#' @param store An initialized `kg_store`.
#' @param path Optional edited bundle directory. The default uses the managed
#'   OKF directory.
#'
#' @return A deterministic, tamper-evident `kg_okf_import_plan`.
#' @export
kg_plan_okf_import <- function(store, path = NULL) {
  validate_retrieval_store(store)
  status <- kg_okf_status(store, path = path)
  if (!status$status %in% c("current", "modified")) {
    abort_okf_import(
      paste0(
        "Cannot plan an OKF import from a `",
        status$status,
        "` bundle. ",
        status$reason
      ),
      okf_status = status
    )
  }
  if (!identical(status$expected_batch_id, status$observed_batch_id)) {
    abort_okf_import(
      "The edited OKF bundle is based on stale accepted knowledge.",
      okf_status = status
    )
  }
  snapshot <- okf_snapshot_bundle(status$path)
  on.exit(unlink(snapshot$path, recursive = TRUE, force = TRUE), add = TRUE)
  if (
    identical(status$status, "current") &&
      !identical(snapshot$bundle_digest, status$bundle_digest)
  ) {
    abort_okf_import(
      paste(
        "The managed OKF bundle changed while creating a planning snapshot.",
        "Retry after filesystem writes have finished."
      ),
      expected_bundle_digest = status$bundle_digest,
      observed_bundle_digest = snapshot$bundle_digest
    )
  }
  index <- okf_parse_frontmatter(file.path(snapshot$path, "index.md"))
  if (!identical(scalar_character(index$graft$scope), "complete")) {
    abort_okf_import(
      "Only a complete managed OKF bundle can be imported.",
      observed_scope = index$graft$scope
    )
  }

  current <- okf_import_current_records(store)
  proposals <- okf_import_proposals(store, snapshot$path)
  removed <- setdiff(names(current), names(proposals))
  if (length(removed) > 0L) {
    abort_okf_import(
      paste0(
        "Removing OKF concept files is not supported; restore ",
        length(removed),
        " accepted concept(s) before planning."
      ),
      removed_record_ids = sort(removed, method = "radix")
    )
  }

  changes <- list()
  changed_records <- list()
  for (record_id in sort(names(proposals), method = "radix")) {
    proposal <- proposals[[record_id]]
    base <- current[[record_id]]
    proposed_digest <- okf_public_record_digest(proposal$record)
    if (is.null(base)) {
      action <- "insert"
      base_digest <- NA_character_
    } else {
      base_digest <- base$digest
      declared_base <- proposal$base_digest
      if (
        is.na(declared_base) ||
          !identical(declared_base, base_digest)
      ) {
        abort_okf_import(
          paste0(
            "Concept `",
            record_id,
            "` is not based on its current accepted revision."
          ),
          record_id = record_id,
          expected_digest = base_digest,
          observed_digest = declared_base
        )
      }
      if (identical(proposed_digest, base_digest)) {
        next
      }
      action <- "update"
    }
    fields <- okf_import_changed_fields(
      if (is.null(base)) list() else base$record,
      proposal$record
    )
    changes[[length(changes) + 1L]] <- data.frame(
      action = action,
      class = proposal$class,
      record_id = record_id,
      changed_fields = paste(fields, collapse = ", "),
      base_digest = base_digest,
      proposed_digest = proposed_digest,
      stringsAsFactors = FALSE
    )
    class_records <- changed_records[[proposal$class]]
    class_records[[length(class_records) + 1L]] <- proposal$record
    changed_records[[proposal$class]] <- class_records
  }
  changes <- if (length(changes) == 0L) {
    empty_okf_import_changes()
  } else {
    do.call(rbind, changes)
  }
  records <- okf_import_data_frames(store, changed_records)
  metadata <- read_store_metadata(store$connection)
  base_batch_id <- if (is.na(status$expected_batch_id)) {
    ""
  } else {
    status$expected_batch_id
  }
  data <- okf_import_plan_data(
    store_id = scalar_character(metadata$store_id),
    schema_build_digest = scalar_character(
      store$schema$manifest$fingerprints$build_digest
    ),
    structural_digest = store_schema_digest(store),
    base_batch_id = base_batch_id,
    path = status$path,
    base_bundle_digest = status$bundle_digest,
    proposed_bundle_digest = snapshot$bundle_digest,
    changes = changes,
    records = records
  )
  structure(
    c(data, list(plan_digest = okf_import_plan_digest(data))),
    class = "kg_okf_import_plan"
  )
}

#' Apply an approved Open Knowledge Format import plan
#'
#' Revalidates the plan, bundle digest, store identity, schema, and accepted
#' batch before committing its records through [kg_ingest()]. After a
#' successful commit, Graft synchronizes the working tree back to the canonical
#' accepted projection.
#'
#' @param store An initialized, writable `kg_store`.
#' @param plan A `kg_okf_import_plan` returned by
#'   [kg_plan_okf_import()].
#' @param batch A [kg_batch()] describing the approved import.
#'
#' @return A `kg_ingest_result`. The synchronized `kg_okf_bundle` is available
#'   in the `okf_bundle` attribute.
#' @export
kg_apply_okf_import <- function(store, plan, batch) {
  validate_initialized_store_for_ingest(store, write = TRUE)
  plan <- validate_okf_import_plan(plan)
  batch <- as_kg_batch(batch)
  if (nrow(plan$changes) == 0L) {
    abort_okf_import("The OKF import plan contains no record changes.")
  }

  metadata <- read_store_metadata(store$connection)
  current_batch <- scalar_character(
    okf_current_boundary(store)$batch_id,
    ""
  )
  observed_digest <- if (dir.exists(plan$path)) {
    okf_bundle_digest(plan$path)
  } else {
    NA_character_
  }
  preconditions <- identical(
    scalar_character(metadata$store_id),
    plan$store_id
  ) &&
    identical(
      scalar_character(metadata$active_build_digest),
      plan$schema_build_digest
    ) &&
    identical(store_schema_digest(store), plan$structural_digest) &&
    identical(current_batch, plan$base_batch_id) &&
    identical(observed_digest, plan$proposed_bundle_digest)
  if (!preconditions) {
    abort_okf_import(
      paste(
        "The store or edited OKF bundle changed after planning.",
        "Create and review a new import plan."
      ),
      expected_batch_id = plan$base_batch_id,
      observed_batch_id = current_batch,
      expected_bundle_digest = plan$proposed_bundle_digest,
      observed_bundle_digest = observed_digest
    )
  }
  report <- kg_validate_data(store, plan$records)
  if (!isTRUE(report$valid)) {
    abort_okf_import(
      "The planned OKF records no longer satisfy the active Graft schema.",
      validation_report = report
    )
  }

  result <- kg_ingest(store, batch = batch, records = plan$records)
  bundle <- tryCatch(
    kg_sync_okf(store, path = plan$path),
    error = function(error) {
      rlang::warn(
        paste(
          "The OKF import committed, but the managed bundle could not be",
          "synchronized. Run `kg_sync_okf()` after correcting the filesystem",
          "problem."
        ),
        class = "graft_okf_sync_warning",
        parent = error
      )
      NULL
    }
  )
  attr(result, "okf_bundle") <- bundle
  result
}

abort_okf_import <- function(message, ..., call = rlang::caller_env()) {
  graft_abort(
    "graft_okf_import_error",
    message,
    ...,
    call = call
  )
}

okf_import_current_records <- function(store) {
  snapshot <- okf_snapshot_records(
    store,
    sort(public_class_names(store), method = "radix"),
    okf_current_boundary(store),
    graft_retrieval_limits$okf_concepts
  )
  result <- list()
  for (item in snapshot) {
    record <- okf_editable_record(item$record, item$contract)
    record_id <- item$metadata$record_id[[1L]]
    result[[record_id]] <- list(
      class = item$metadata$class[[1L]],
      record = record,
      digest = okf_public_record_digest(record)
    )
  }
  result
}

okf_import_proposals <- function(store, path) {
  files <- okf_concept_files(path)
  proposals <- list()
  for (file in files) {
    frontmatter <- okf_parse_frontmatter(file)
    graft <- frontmatter$graft
    if (!is.list(graft) || is.null(names(graft))) {
      abort_okf_import(
        paste0(
          "Concept `",
          basename(file),
          "` does not contain an editable Graft record mapping."
        ),
        path = file
      )
    }
    record_class <- scalar_character(graft$class, NA_character_)
    record_id <- scalar_character(graft$record_id, NA_character_)
    profile <- scalar_character(graft$profile, "graft-okf")
    record <- graft$record
    if (
      is.na(record_class) ||
        is.na(record_id) ||
        !identical(profile, "graft-okf") ||
        !is.list(record) ||
        is.null(names(record))
    ) {
      abort_okf_import(
        paste0(
          "Concept `",
          basename(file),
          "` does not contain an editable Graft record mapping."
        ),
        path = file
      )
    }
    if (!identical(scalar_character(frontmatter$type), record_class)) {
      abort_okf_import(
        "An OKF concept type does not match its Graft class.",
        path = file,
        record_id = record_id,
        record_class = record_class
      )
    }
    contract <- store$schema$manifest$classes[[record_class]]
    if (is.null(contract)) {
      abort_okf_import(
        paste0("Unknown Graft class `", record_class, "`."),
        path = file,
        record_class = record_class
      )
    }
    okf_validate_import_record(record, contract, record_id, file)
    record <- okf_normalize_import_record(record, contract)
    if (!is.null(proposals[[record_id]])) {
      abort_okf_import(
        paste0("Record `", record_id, "` appears in more than one concept."),
        record_id = record_id
      )
    }
    proposals[[record_id]] <- list(
      class = record_class,
      record = record,
      base_digest = scalar_character(
        graft$public_content_digest,
        NA_character_
      ),
      path = file
    )
  }
  proposals
}

okf_normalize_import_record <- function(record, contract) {
  fields <- names(contract$slots)
  fields <- fields[fields %in% names(record)]
  record <- record[fields]
  for (field in fields) {
    slot <- contract$slots[[field]]
    value <- record[[field]]
    if (is.null(value)) {
      next
    }
    if (scalar_logical(slot$multivalued)) {
      values <- unlist(value, use.names = FALSE)
      type <- okf_import_slot_type(slot)
      values <- switch(
        type,
        BOOLEAN = as.logical(values),
        BIGINT = as.numeric(values),
        DOUBLE = as.numeric(values),
        DECIMAL = as.numeric(values),
        as.character(values)
      )
      record[[field]] <- unname(as.list(values))
    } else {
      record[[field]] <- okf_import_scalar_column(list(value), slot)[[1L]]
    }
  }
  record
}

okf_validate_import_record <- function(record, contract, record_id, path) {
  generated <- c("created_at", "updated_at")
  allowed <- setdiff(
    names(Filter(
      \(.x) !scalar_logical(.x$sensitive),
      contract$slots
    )),
    generated
  )
  unknown <- setdiff(names(record), allowed)
  if (length(unknown) > 0L) {
    abort_okf_import(
      paste0(
        "Editable record `",
        record_id,
        "` contains unsupported field(s): ",
        paste(sort(unknown, method = "radix"), collapse = ", "),
        "."
      ),
      path = path,
      record_id = record_id,
      fields = unknown
    )
  }
  identifiers <- names(Filter(
    \(.x) scalar_logical(.x$identifier),
    contract$slots
  ))
  if (length(identifiers) != 1L) {
    abort_okf_import(
      "An importable Graft class must declare exactly one identifier slot.",
      path = path,
      record_id = record_id,
      identifier_slots = identifiers
    )
  }
  observed_id <- scalar_character(record[[identifiers[[1L]]]], NA_character_)
  if (!identical(observed_id, record_id)) {
    abort_okf_import(
      "The editable record identifier does not match its Graft record ID.",
      path = path,
      record_id = record_id,
      observed_id = observed_id
    )
  }
  invisible(record)
}

okf_import_changed_fields <- function(old, new) {
  fields <- union(names(old), names(new))
  fields[vapply(
    fields,
    function(field) {
      !identical(
        canonical_json(list(value = old[[field]])),
        canonical_json(list(value = new[[field]]))
      )
    },
    logical(1)
  )] |>
    sort(method = "radix")
}

okf_import_data_frames <- function(store, records) {
  if (length(records) == 0L) {
    return(list())
  }
  result <- lapply(names(records), function(record_class) {
    contract <- store$schema$manifest$classes[[record_class]]
    class_records <- records[[record_class]]
    fields <- unique(unlist(lapply(class_records, names), use.names = FALSE))
    fields <- names(contract$slots)[names(contract$slots) %in% fields]
    columns <- lapply(fields, function(field) {
      slot <- contract$slots[[field]]
      values <- lapply(class_records, \(.x) .x[[field]])
      if (scalar_logical(slot$multivalued)) {
        return(I(values))
      }
      okf_import_scalar_column(values, slot)
    })
    names(columns) <- fields
    as.data.frame(
      columns,
      stringsAsFactors = FALSE,
      check.names = FALSE,
      optional = TRUE
    )
  })
  names(result) <- names(records)
  result
}

okf_import_scalar_column <- function(values, slot) {
  type <- okf_import_slot_type(slot)
  missing_value <- switch(
    type,
    BOOLEAN = NA,
    BIGINT = NA_real_,
    DOUBLE = NA_real_,
    DECIMAL = NA_real_,
    NA_character_
  )
  values <- lapply(values, function(value) {
    if (is.null(value) || length(value) == 0L) {
      return(missing_value)
    }
    value[[1L]]
  })
  switch(
    type,
    BOOLEAN = as.logical(unlist(values, use.names = FALSE)),
    BIGINT = as.numeric(unlist(values, use.names = FALSE)),
    DOUBLE = as.numeric(unlist(values, use.names = FALSE)),
    DECIMAL = as.numeric(unlist(values, use.names = FALSE)),
    as.character(unlist(values, use.names = FALSE))
  )
}

okf_import_slot_type <- function(slot) {
  toupper(scalar_character(
    slot$duckdb_type,
    scalar_character(slot$relational_type, "VARCHAR")
  ))
}

empty_okf_import_changes <- function() {
  data.frame(
    action = character(),
    class = character(),
    record_id = character(),
    changed_fields = character(),
    base_digest = character(),
    proposed_digest = character(),
    stringsAsFactors = FALSE
  )
}

okf_import_plan_data <- function(
  store_id,
  schema_build_digest,
  structural_digest,
  base_batch_id,
  path,
  base_bundle_digest,
  proposed_bundle_digest,
  changes,
  records
) {
  list(
    plan_version = okf_import_plan_version,
    store_id = store_id,
    schema_build_digest = schema_build_digest,
    structural_digest = structural_digest,
    base_batch_id = base_batch_id,
    path = path,
    base_bundle_digest = base_bundle_digest,
    proposed_bundle_digest = proposed_bundle_digest,
    changes = changes,
    records = records
  )
}

okf_import_plan_digest <- function(data) {
  paste0(
    "sha256:",
    digest::digest(
      canonical_json(data),
      algo = "sha256",
      serialize = FALSE
    )
  )
}

validate_okf_import_plan <- function(plan) {
  expected_names <- c(
    names(okf_import_plan_data(
      store_id = "",
      schema_build_digest = "",
      structural_digest = "",
      base_batch_id = "",
      path = "",
      base_bundle_digest = "",
      proposed_bundle_digest = "",
      changes = empty_okf_import_changes(),
      records = list()
    )),
    "plan_digest"
  )
  if (
    !inherits(plan, "kg_okf_import_plan") ||
      !is.list(plan) ||
      !identical(names(plan), expected_names) ||
      !is.data.frame(plan$changes) ||
      !identical(names(plan$changes), names(empty_okf_import_changes())) ||
      !all(vapply(plan$changes, is.character, logical(1))) ||
      !is.list(plan$records) ||
      (length(plan$records) > 0L &&
        (is.null(names(plan$records)) ||
          anyNA(names(plan$records)) ||
          !all(nzchar(names(plan$records))) ||
          anyDuplicated(names(plan$records)) ||
          !all(vapply(plan$records, is.data.frame, logical(1)))))
  ) {
    abort_okf_import(
      "`plan` must be an unmodified kg_okf_import_plan object."
    )
  }
  scalar_fields <- setdiff(
    expected_names,
    c("changes", "records")
  )
  valid_scalars <- vapply(
    plan[scalar_fields],
    \(.x) is.character(.x) && length(.x) == 1L && !is.na(.x),
    logical(1)
  )
  if (!all(valid_scalars)) {
    abort_okf_import("The OKF import plan contains invalid fields.")
  }
  if (!identical(plan$plan_version, okf_import_plan_version)) {
    abort_okf_import(
      paste0(
        "Unsupported OKF import plan version `",
        plan$plan_version,
        "`."
      )
    )
  }
  data <- unclass(plan)[setdiff(names(plan), "plan_digest")]
  expected_digest <- tryCatch(
    okf_import_plan_digest(data),
    error = function(error) {
      abort_okf_import(
        "The OKF import plan contains data that cannot be verified.",
        parent = error
      )
    }
  )
  if (!identical(plan$plan_digest, expected_digest)) {
    abort_okf_import(
      "The OKF import plan digest is invalid; the plan may have been modified.",
      expected_digest = expected_digest,
      observed_digest = plan$plan_digest
    )
  }
  plan
}
