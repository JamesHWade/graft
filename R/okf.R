# Open Knowledge Format export

graft_okf_version <- "0.2"
graft_okf_profile_version <- "1"

#' Export accepted Graft knowledge as an Open Knowledge Format bundle
#'
#' `kg_export_okf()` writes a deterministic
#' [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf)
#' (OKF) v0.2 directory from accepted Graft revisions. The bundle is a
#' human-readable projection for agents, Git, and documentation tools. The
#' active LinkML-derived manifest remains the executable contract for identity,
#' validation, storage, and retrieval.
#'
#' Every concept includes a `graft` frontmatter extension with stable record,
#' revision, batch, and schema identity. Object references become Markdown
#' links, and direct or claim-evidence source references become OKF `sources`.
#' Sensitive slots remain excluded through the historical manifest that
#' governed each exported revision.
#'
#' Exports are bounded and atomic. Existing directories are never replaced
#' unless `overwrite = TRUE` and the directory identifies itself as a
#' Graft-produced OKF bundle. The managed directory is reserved for a complete
#' projection of current accepted state; selected or historical exports must
#' use another `path`.
#'
#' @param store An initialized `kg_store`.
#' @param path Destination directory. The default uses the store's managed OKF
#'   directory. It need not already exist.
#' @param classes Optional concrete classes to export. The default exports all
#'   public classes in the active manifest.
#' @param as_of Optional committed batch identifier or scalar `POSIXt` time.
#'   The default exports current accepted record heads.
#' @param limit Maximum number of concepts. An export that exceeds the limit
#'   fails rather than writing a partial bundle.
#' @param overwrite Whether to replace an existing Graft-produced OKF bundle.
#'
#' @return A `kg_okf_bundle` summary.
#' @examples
#' \dontrun{
#' bundle <- kg_export_okf(store, "knowledge/okf")
#' bundle
#' }
#' @export
kg_export_okf <- function(
  store,
  path = NULL,
  classes = NULL,
  as_of = NULL,
  limit = 5000,
  overwrite = FALSE
) {
  validate_retrieval_store(store)
  path <- okf_resolve_path(store, path)
  if (
    !is.null(store$okf_path) &&
      identical(path, store$okf_path) &&
      (!is.null(classes) || !is.null(as_of))
  ) {
    abort_validation_error(
      paste(
        "The managed OKF directory must remain a complete projection of",
        "current accepted state. Supply a different `path` for selected or",
        "historical exports."
      ),
      field = "path",
      rule = "managed_okf_current_complete",
      observed_value = path
    )
  }
  path <- okf_output_path(path)
  classes <- okf_export_classes(store, classes)
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$okf_concepts
  )
  overwrite <- validate_history_flag(overwrite, "overwrite")
  boundary <- if (is.null(as_of)) {
    okf_current_boundary(store)
  } else {
    resolve_history_boundary(store, as_of)
  }
  bundle_schema <- okf_boundary_schema(store, boundary)
  snapshot <- okf_snapshot_records(store, classes, boundary, limit)
  bundle <- okf_build_bundle(
    path,
    snapshot,
    boundary,
    bundle_schema,
    overwrite,
    classes
  )
  structure(bundle, class = "kg_okf_bundle")
}

okf_output_path <- function(path) {
  path <- validate_scalar_text(path, "path")
  path <- path.expand(path)
  if (!grepl("^(/|[A-Za-z]:[/\\\\])", path)) {
    path <- file.path(getwd(), path)
  }
  parent <- dirname(path)
  if (!dir.exists(parent) && !dir.create(parent, recursive = TRUE)) {
    abort_backend_error(
      paste0("Could not create the OKF parent directory `", parent, "`."),
      operation = "export_okf",
      path = path
    )
  }
  parent <- normalizePath(parent, winslash = "/", mustWork = TRUE)
  file.path(parent, basename(path))
}

okf_export_classes <- function(store, classes) {
  available <- sort(public_class_names(store), method = "radix")
  if (is.null(classes)) {
    return(available)
  }
  if (
    !is.character(classes) ||
      length(classes) == 0L ||
      anyNA(classes) ||
      any(!nzchar(classes))
  ) {
    abort_validation_error(
      "`classes` must contain one or more non-empty class names.",
      field = "classes",
      rule = "public_concrete_classes",
      observed_value = classes
    )
  }
  classes <- unique(classes)
  unknown <- setdiff(classes, available)
  if (length(unknown) > 0L) {
    abort_validation_error(
      paste0(
        "Unknown public concrete class(es): ",
        paste(unknown, collapse = ", "),
        "."
      ),
      field = "classes",
      rule = "public_concrete_classes",
      observed_value = unknown
    )
  }
  sort(classes, method = "radix")
}

okf_snapshot_records <- function(store, classes, boundary, limit) {
  class_placeholders <- paste(rep("?", length(classes)), collapse = ", ")
  boundary_sql <- if (is.null(boundary$commit_order)) {
    ""
  } else {
    " AND r.commit_order <= ?"
  }
  params <- c(
    as.list(classes),
    if (is.null(boundary$commit_order)) {
      list()
    } else {
      list(boundary$commit_order)
    }
  )
  sql <- paste0(
    "SELECT * EXCLUDE (snapshot_rank) FROM (",
    "SELECT r.revision_id, r.record_id, r.class, r.batch_id, ",
    "r.schema_build_digest, r.revision_number, r.payload_json, ",
    "r.content_digest, r.commit_order, b.committed_at, b.producer, ",
    "b.producer_version, b.source_run_id, ",
    "ROW_NUMBER() OVER (PARTITION BY r.class, r.record_id ",
    "ORDER BY r.revision_number DESC, r.revision_id ASC) AS snapshot_rank ",
    "FROM ",
    quote_identifier(store$connection, "_graft_record_revisions"),
    " r INNER JOIN ",
    quote_identifier(store$connection, "_graft_batches"),
    " b ON r.batch_id = b.batch_id ",
    "WHERE b.status = 'committed' AND r.class IN (",
    class_placeholders,
    ")",
    boundary_sql,
    ") snapshot WHERE snapshot_rank = 1 ",
    "ORDER BY class, record_id LIMIT ",
    limit + 1L
  )
  rows <- with_duckdb_error(
    "export_okf_snapshot",
    DBI::dbGetQuery(store$connection, sql, params = params)
  )
  if (nrow(rows) > limit) {
    abort_limit_error(
      paste0(
        "The OKF export contains more than ",
        limit,
        " concepts; no partial bundle was written."
      ),
      argument = "limit",
      requested_limit = limit,
      hard_limit = graft_retrieval_limits$okf_concepts,
      observed_count = nrow(rows)
    )
  }

  cache <- new.env(parent = emptyenv())
  records <- vector("list", nrow(rows))
  for (index in seq_len(nrow(rows))) {
    schema <- historical_schema(
      store,
      rows$schema_build_digest[[index]],
      cache
    )
    contract <- schema$manifest$classes[[rows$class[[index]]]]
    if (is.null(contract)) {
      abort_backend_error(
        "An OKF snapshot revision is absent from its historical manifest.",
        operation = "export_okf_snapshot",
        record_id = rows$record_id[[index]],
        record_class = rows$class[[index]]
      )
    }
    records[[index]] <- list(
      metadata = as.list(rows[index, , drop = FALSE]),
      record = public_revision_record(
        rows$payload_json[[index]],
        contract
      ),
      contract = contract
    )
  }
  records
}

okf_boundary_schema <- function(store, boundary) {
  if (
    is.null(boundary$commit_order) ||
      is.null(boundary$batch_id) ||
      is.na(boundary$batch_id)
  ) {
    return(store$schema)
  }
  row <- with_duckdb_error(
    "export_okf_schema",
    DBI::dbGetQuery(
      store$connection,
      paste0(
        "SELECT schema_build_digest FROM ",
        quote_identifier(store$connection, "_graft_batches"),
        " WHERE batch_id = ? AND status = 'committed'"
      ),
      params = list(boundary$batch_id)
    )
  )
  if (nrow(row) != 1L) {
    abort_backend_error(
      "The OKF boundary does not have exactly one committed schema.",
      operation = "export_okf_schema",
      batch_id = boundary$batch_id,
      schema_count = nrow(row)
    )
  }
  historical_schema(
    store,
    row$schema_build_digest[[1L]],
    new.env(parent = emptyenv())
  )
}

okf_build_bundle <- function(
  path,
  snapshot,
  boundary,
  bundle_schema,
  overwrite,
  export_classes
) {
  okf_check_destination(path, overwrite)
  stage <- tempfile(
    pattern = paste0(".", basename(path), "-"),
    tmpdir = dirname(path)
  )
  if (!dir.create(stage)) {
    abort_backend_error(
      "Could not create an OKF staging directory.",
      operation = "export_okf",
      path = stage
    )
  }
  on.exit(
    if (dir.exists(stage)) unlink(stage, recursive = TRUE, force = TRUE),
    add = TRUE
  )

  path_map <- okf_snapshot_path_map(snapshot)
  concept_lookup <- okf_snapshot_lookup(snapshot, path_map)
  concepts <- lapply(seq_along(snapshot), function(index) {
    okf_snapshot_concept(
      snapshot[[index]],
      path_map[[index]],
      concept_lookup
    )
  })
  okf_write_concepts(stage, concepts)
  bundle_digest <- okf_write_indexes(
    stage,
    bundle_schema,
    concepts,
    boundary,
    export_classes
  )
  okf_validate_staged_bundle(stage, length(concepts))
  okf_install_staged_bundle(stage, path, overwrite)

  latest <- okf_snapshot_latest_time(snapshot, boundary)
  list(
    path = normalizePath(path, winslash = "/", mustWork = TRUE),
    okf_version = graft_okf_version,
    profile_version = graft_okf_profile_version,
    concept_count = length(concepts),
    classes = sort(
      unique(vapply(
        concepts,
        \(.x) .x$class,
        character(1)
      )),
      method = "radix"
    ),
    schema_build_digest = scalar_character(
      bundle_schema$manifest$fingerprints$build_digest
    ),
    structural_digest = scalar_character(
      bundle_schema$manifest$fingerprints$structural_digest
    ),
    bundle_digest = bundle_digest,
    as_of_batch_id = boundary$batch_id,
    as_of_committed_at = latest
  )
}

okf_snapshot_path_map <- function(snapshot) {
  paths <- vapply(
    snapshot,
    function(item) {
      file.path(
        "concepts",
        utils::URLencode(item$metadata$class[[1L]], reserved = TRUE),
        paste0(
          utils::URLencode(item$metadata$record_id[[1L]], reserved = TRUE),
          ".md"
        )
      )
    },
    character(1)
  )
  gsub("\\\\", "/", paths)
}

okf_snapshot_lookup <- function(snapshot, path_map) {
  lookup <- new.env(parent = emptyenv())
  class_roles <- character()
  role_items <- list()
  for (index in seq_along(snapshot)) {
    item <- snapshot[[index]]
    id <- item$metadata$record_id[[1L]]
    title <- okf_record_title(item$record, item$contract, id)
    candidate <- list(
      item = item,
      path = path_map[[index]],
      title = title
    )
    assign(id, candidate, envir = lookup)
    role <- scalar_character(item$contract$role, "node")
    class <- item$metadata$class[[1L]]
    class_roles[[class]] <- role
    role_candidates <- role_items[[role]]
    role_candidates[[length(role_candidates) + 1L]] <- candidate
    role_items[[role]] <- role_candidates
  }
  evidence_sources <- list()
  evidence <- role_items$evidence
  if (is.null(evidence)) {
    evidence <- list()
  }
  for (candidate in evidence) {
    statement_id <- okf_scalar_text(candidate$item$record$statement_id)
    if (is.null(statement_id)) {
      next
    }
    evidence_sources[[statement_id]] <- c(
      evidence_sources[[statement_id]],
      okf_reference_values(candidate$item$record$source_id)
    )
  }
  attr(lookup, "class_roles") <- class_roles
  attr(lookup, "evidence_sources") <- lapply(
    evidence_sources,
    \(.x) sort(unique(.x), method = "radix")
  )
  lookup
}

okf_snapshot_concept <- function(item, path, lookup) {
  metadata <- item$metadata
  record <- item$record
  contract <- item$contract
  id <- metadata$record_id[[1L]]
  title <- okf_record_title(record, contract, id)
  description <- okf_record_description(record, title)
  sources <- okf_record_sources(item, lookup)
  frontmatter <- okf_record_frontmatter(
    item,
    title,
    description,
    sources$entries
  )
  body <- okf_record_body(
    item,
    title,
    description,
    sources,
    lookup
  )
  list(
    class = metadata$class[[1L]],
    id = id,
    path = path,
    title = title,
    description = description,
    frontmatter = frontmatter,
    body = body
  )
}

okf_record_title <- function(record, contract, id) {
  candidates <- unique(c(
    scalar_character(contract$label_slot),
    "title",
    "name",
    "headline",
    "preferred_name",
    "statement",
    "statement_text"
  ))
  for (candidate in candidates) {
    value <- okf_scalar_text(record[[candidate]])
    if (!is.null(value)) {
      return(okf_heading_text(value))
    }
  }
  id
}

okf_record_description <- function(record, title) {
  candidates <- c(
    "description",
    "summary",
    "statement",
    "statement_text",
    "implication",
    "text"
  )
  for (candidate in candidates) {
    value <- okf_scalar_text(record[[candidate]])
    if (!is.null(value) && !identical(value, title)) {
      return(gsub("[\r\n]+", " ", value))
    }
  }
  NULL
}

okf_scalar_text <- function(value) {
  if (
    is.null(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !nzchar(trimws(as.character(value)))
  ) {
    return(NULL)
  }
  trimws(as.character(value))
}

okf_record_frontmatter <- function(
  item,
  title,
  description,
  sources
) {
  metadata <- item$metadata
  record <- item$record
  contract <- item$contract
  role <- scalar_character(contract$role, "node")
  status <- okf_record_status(record)
  stale_after <- okf_record_date(record$stale_after)
  editable_record <- okf_editable_record(record, contract)
  tags <- unique(c(metadata$class[[1L]], if (!identical(role, "node")) role))
  frontmatter <- list(
    type = metadata$class[[1L]],
    title = title,
    description = description,
    resource = paste0(
      "graft://record/",
      utils::URLencode(metadata$record_id[[1L]], reserved = TRUE)
    ),
    tags = tags,
    status = status,
    stale_after = stale_after,
    generated = list(
      by = okf_batch_actor(
        metadata$producer[[1L]],
        metadata$producer_version[[1L]]
      ),
      at = okf_datetime(metadata$committed_at[[1L]])
    ),
    sources = if (length(sources) == 0L) NULL else sources,
    graft = list(
      profile = "graft-okf",
      profile_version = graft_okf_profile_version,
      record_id = metadata$record_id[[1L]],
      class = metadata$class[[1L]],
      role = role,
      revision_id = metadata$revision_id[[1L]],
      revision_number = as.integer(metadata$revision_number[[1L]]),
      batch_id = metadata$batch_id[[1L]],
      source_run_id = okf_optional_value(metadata$source_run_id[[1L]]),
      schema_build_digest = metadata$schema_build_digest[[1L]],
      content_digest = metadata$content_digest[[1L]],
      public_content_digest = okf_public_record_digest(editable_record),
      record = editable_record
    )
  )
  okf_compact(frontmatter)
}

okf_record_status <- function(record) {
  value <- tolower(okf_default(okf_scalar_text(record$status), "stable"))
  if (value %in% c("draft", "proposed", "pending")) {
    return("draft")
  }
  if (value %in% c("deprecated", "superseded", "retired", "inactive")) {
    return("deprecated")
  }
  "stable"
}

okf_record_date <- function(value) {
  if (is.null(value) || length(value) != 1L || is.na(value)) {
    return(NULL)
  }
  if (inherits(value, "Date")) {
    return(format(value, "%Y-%m-%d"))
  }
  value <- as.character(value)
  if (grepl("^\\d{4}-\\d{2}-\\d{2}$", value)) value else NULL
}

okf_optional_value <- function(value) {
  if (is.null(value) || length(value) == 0L || is.na(value)) NULL else value
}

okf_editable_record <- function(record, contract) {
  fields <- setdiff(
    names(record),
    c("created_at", "updated_at")
  )
  result <- record[fields]
  for (field in fields) {
    slot <- contract$slots[[field]]
    value <- result[[field]]
    if (is.null(slot) || is.null(value)) {
      next
    }
    if (inherits(value, "POSIXt")) {
      result[[field]] <- okf_datetime(value)
    } else if (inherits(value, "Date")) {
      result[[field]] <- format(value, "%Y-%m-%d")
    } else if (inherits(value, "difftime")) {
      result[[field]] <- as.character(value)
    } else if (scalar_logical(slot$multivalued)) {
      result[[field]] <- unname(as.list(value))
    }
  }
  okf_compact(result)
}

okf_public_record_digest <- function(record) {
  paste0(
    "sha256:",
    digest::digest(
      canonical_json(record),
      algo = "sha256",
      serialize = FALSE
    )
  )
}

okf_datetime <- function(value) {
  format(
    as.POSIXct(value, tz = "UTC"),
    "%Y-%m-%dT%H:%M:%SZ",
    tz = "UTC"
  )
}

okf_batch_actor <- function(producer, version) {
  producer <- okf_default(okf_scalar_text(producer), "graft")
  if (startsWith(producer, "human:") || startsWith(producer, "process:")) {
    return(producer)
  }
  producer <- gsub("[^A-Za-z0-9._-]+", "-", producer)
  producer <- gsub("(^-+|-+$)", "", producer)
  if (!nzchar(producer)) {
    producer <- "graft"
  }
  version <- okf_default(okf_scalar_text(version), "unknown")
  version <- gsub("[^A-Za-z0-9._-]+", "-", version)
  paste0(producer, "/", version)
}

okf_record_sources <- function(item, lookup) {
  record <- item$record
  contract <- item$contract
  source_ids <- character()
  for (slot_name in names(contract$slots)) {
    slot <- contract$slots[[slot_name]]
    if (!scalar_logical(slot$object_reference)) {
      next
    }
    target_role <- okf_lookup_role(lookup, scalar_character(slot$range))
    source_slot <- tolower(slot_name) %in%
      c(
        "source",
        "source_id",
        "sources",
        "source_documents"
      )
    if (!source_slot && !identical(target_role, "source")) {
      next
    }
    source_ids <- c(source_ids, okf_reference_values(record[[slot_name]]))
  }

  if (identical(scalar_character(contract$role), "statement")) {
    statement_id <- item$metadata$record_id[[1L]]
    evidence_sources <- attr(lookup, "evidence_sources", exact = TRUE)
    source_ids <- c(source_ids, evidence_sources[[statement_id]])
  }

  source_ids <- sort(unique(source_ids), method = "radix")
  entries <- list()
  labels <- character()
  for (source_id in source_ids) {
    if (!exists(source_id, envir = lookup, inherits = FALSE)) {
      next
    }
    source <- get(source_id, envir = lookup, inherits = FALSE)
    label <- paste0(
      "source-",
      substr(
        digest::digest(source_id, algo = "sha256", serialize = FALSE),
        1L,
        12L
      )
    )
    uri <- okf_source_uri(source$item$record)
    entries[[length(entries) + 1L]] <- list(
      id = label,
      resource = okf_default(uri, paste0("/", source$path)),
      title = source$title
    )
    labels[[length(labels) + 1L]] <- label
  }
  list(entries = entries, labels = labels)
}

okf_lookup_role <- function(lookup, class) {
  class_roles <- attr(lookup, "class_roles", exact = TRUE)
  role <- unname(class_roles[class])
  if (length(role) == 0L || is.na(role) || !nzchar(role)) {
    return("node")
  }
  role
}

okf_source_uri <- function(record) {
  for (field in c("uri", "url", "locator", "doi")) {
    value <- okf_scalar_text(record[[field]])
    if (!is.null(value)) {
      return(value)
    }
  }
  NULL
}

okf_record_body <- function(
  item,
  title,
  description,
  sources,
  lookup
) {
  record <- item$record
  contract <- item$contract
  lines <- c(paste0("# ", okf_heading_text(title)))
  statement_field <- intersect(
    c("statement", "statement_text", "text"),
    names(record)
  )
  statement <- if (length(statement_field) > 0L) {
    okf_scalar_text(record[[statement_field[[1L]]]])
  } else {
    NULL
  }
  if (!is.null(statement)) {
    citation_marks <- paste0("[^", sources$labels, "]", collapse = "")
    lines <- c(lines, "", "## Statement", "", paste0(statement, citation_marks))
  } else if (!is.null(description)) {
    citation_marks <- paste0("[^", sources$labels, "]", collapse = "")
    lines <- c(lines, "", "## Summary", "", paste0(description, citation_marks))
  }

  relationships <- okf_relationship_lines(record, contract, lookup)
  if (length(relationships) > 0L) {
    lines <- c(lines, "", "## Relationships", "", relationships)
  }

  excluded <- unique(c(
    "id",
    scalar_character(contract$label_slot),
    statement_field,
    "description",
    "summary",
    "created_at",
    "updated_at",
    names(Filter(\(.x) scalar_logical(.x$object_reference), contract$slots))
  ))
  details <- okf_detail_rows(record, contract, excluded)
  if (length(details) > 0L) {
    lines <- c(
      lines,
      "",
      "## Details",
      "",
      "| Field | Value |",
      "|---|---|",
      details
    )
  }

  if (length(sources$labels) > 0L) {
    source_titles <- stats::setNames(
      vapply(
        sources$entries,
        \(.x) .x$title,
        character(1)
      ),
      sources$labels
    )
    footnotes <- paste0(
      "[^",
      names(source_titles),
      "]: ",
      unname(source_titles)
    )
    lines <- c(lines, "", footnotes)
  }
  paste(lines, collapse = "\n")
}

okf_heading_text <- function(value) {
  gsub("[\r\n]+", " ", value)
}

okf_relationship_lines <- function(record, contract, lookup) {
  lines <- character()
  for (slot_name in names(contract$slots)) {
    slot <- contract$slots[[slot_name]]
    if (
      !scalar_logical(slot$object_reference) ||
        scalar_logical(slot$sensitive)
    ) {
      next
    }
    values <- okf_reference_values(record[[slot_name]])
    if (length(values) == 0L) {
      next
    }
    rendered <- vapply(
      values,
      function(value) {
        if (!exists(value, envir = lookup, inherits = FALSE)) {
          return(paste0("`", okf_inline_code(value), "`"))
        }
        target <- get(value, envir = lookup, inherits = FALSE)
        paste0(
          "[",
          okf_link_text(target$title),
          "](/",
          target$path,
          ")"
        )
      },
      character(1)
    )
    label <- gsub("_", " ", slot_name, fixed = TRUE)
    label <- paste0(toupper(substr(label, 1L, 1L)), substring(label, 2L))
    lines <- c(
      lines,
      paste0("- **", label, ":** ", paste(rendered, collapse = ", "))
    )
  }
  lines
}

okf_reference_values <- function(value) {
  if (is.null(value) || length(value) == 0L) {
    return(character())
  }
  values <- as.character(unlist(value, use.names = FALSE))
  values[!is.na(values) & nzchar(values)]
}

okf_link_text <- function(value) {
  gsub("([][\\\\])", "\\\\\\1", okf_heading_text(value))
}

okf_inline_code <- function(value) {
  value <- gsub("[\r\n]+", " ", value)
  gsub("`", "\\\\`", value, fixed = TRUE)
}

okf_detail_rows <- function(record, contract, excluded) {
  fields <- setdiff(names(record), excluded)
  rows <- character()
  for (field in fields) {
    slot <- contract$slots[[field]]
    if (is.null(slot) || scalar_logical(slot$sensitive)) {
      next
    }
    value <- okf_render_value(record[[field]])
    if (is.null(value)) {
      next
    }
    rows <- c(
      rows,
      paste0(
        "| `",
        okf_inline_code(field),
        "` | ",
        okf_table_text(value),
        " |"
      )
    )
  }
  rows
}

okf_render_value <- function(value) {
  if (is.null(value) || length(value) == 0L || all(is.na(value))) {
    return(NULL)
  }
  if (inherits(value, "POSIXt")) {
    return(okf_datetime(value))
  }
  if (inherits(value, "Date")) {
    return(format(value, "%Y-%m-%d"))
  }
  values <- as.character(unlist(value, use.names = FALSE))
  values <- values[!is.na(values)]
  if (length(values) == 0L) NULL else paste(values, collapse = ", ")
}

okf_table_text <- function(value) {
  value <- gsub("[\r\n]+", " ", value)
  value <- gsub("\\\\", "\\\\\\\\", value)
  gsub("|", "\\\\|", value, fixed = TRUE)
}

okf_compact <- function(value) {
  if (!is.list(value)) {
    return(value)
  }
  value <- lapply(value, okf_compact)
  keep <- !vapply(
    value,
    function(item) {
      is.null(item) ||
        length(item) == 0L ||
        (length(item) == 1L && is.atomic(item) && is.na(item))
    },
    logical(1)
  )
  value[keep]
}

okf_default <- function(value, default) {
  if (is.null(value)) default else value
}

okf_write_concepts <- function(stage, concepts) {
  for (concept in concepts) {
    destination <- file.path(stage, concept$path)
    if (
      !dir.exists(dirname(destination)) &&
        !dir.create(dirname(destination), recursive = TRUE)
    ) {
      abort_backend_error(
        "Could not create an OKF concept directory.",
        operation = "export_okf",
        path = dirname(destination)
      )
    }
    okf_write_text(
      destination,
      okf_document(concept$frontmatter, concept$body)
    )
  }
}

okf_document <- function(frontmatter, body) {
  yaml <- yaml::as.yaml(
    frontmatter,
    line.sep = "\n",
    precision = 22
  )
  yaml <- sub("\n$", "", yaml)
  paste("---", yaml, "---", body, "", sep = "\n")
}

okf_write_indexes <- function(
  stage,
  schema,
  concepts,
  boundary,
  export_classes
) {
  classes <- sort(
    unique(vapply(
      concepts,
      \(.x) .x$class,
      character(1)
    )),
    method = "radix"
  )
  grouped <- split(
    concepts,
    vapply(
      concepts,
      \(.x) .x$class,
      character(1)
    )
  )
  class_entries <- vapply(
    classes,
    function(class) {
      encoded <- utils::URLencode(class, reserved = TRUE)
      count <- length(grouped[[class]])
      paste0(
        "* [",
        okf_link_text(class),
        "](concepts/",
        encoded,
        "/) - ",
        count,
        if (count == 1L) " concept." else " concepts."
      )
    },
    character(1)
  )
  fingerprints <- schema$manifest$fingerprints
  schema_metadata <- schema$manifest$schema
  index_frontmatter <- okf_compact(list(
    okf_version = graft_okf_version,
    graft = list(
      profile = "graft-okf",
      profile_version = graft_okf_profile_version,
      schema_id = scalar_character(schema_metadata$id),
      schema_name = scalar_character(schema_metadata$name),
      schema_version = scalar_character(schema_metadata$version),
      schema_build_digest = scalar_character(fingerprints$build_digest),
      structural_digest = scalar_character(fingerprints$structural_digest),
      as_of_batch_id = boundary$batch_id,
      as_of_committed_at = if (is.null(boundary$committed_at)) {
        NULL
      } else {
        okf_datetime(boundary$committed_at)
      },
      scope = if (
        setequal(
          export_classes,
          names(schema$manifest$classes)
        )
      ) {
        "complete"
      } else {
        "selected"
      },
      classes = sort(export_classes, method = "radix"),
      concept_count = length(concepts)
    )
  ))
  title <- scalar_character(schema_metadata$name, "Graft knowledge")
  body <- c(
    paste0("# ", title),
    "",
    paste(
      "This Open Knowledge Format bundle is a portable projection of accepted",
      "Graft revisions. Its `graft` metadata preserves the governing schema,",
      "batch, revision, and stable record identity."
    ),
    "",
    "# Concepts",
    "",
    if (length(class_entries) == 0L) {
      "No concepts were accepted at this boundary."
    } else {
      class_entries
    }
  )
  okf_write_text(
    file.path(stage, "index.md"),
    okf_document(index_frontmatter, paste(body, collapse = "\n"))
  )

  concepts_index <- c(
    "# Concepts",
    "",
    if (length(class_entries) == 0L) {
      "No concepts were accepted at this boundary."
    } else {
      sub("](concepts/", "](", class_entries, fixed = TRUE)
    }
  )
  if (!dir.exists(file.path(stage, "concepts"))) {
    dir.create(file.path(stage, "concepts"))
  }
  okf_write_text(
    file.path(stage, "concepts", "index.md"),
    paste(c(concepts_index, ""), collapse = "\n")
  )

  for (class in classes) {
    class_concepts <- grouped[[class]]
    class_concepts <- class_concepts[order(
      vapply(
        class_concepts,
        \(.x) .x$title,
        character(1)
      ),
      method = "radix"
    )]
    entries <- vapply(
      class_concepts,
      function(concept) {
        description <- if (is.null(concept$description)) {
          ""
        } else {
          paste0(" - ", concept$description)
        }
        paste0(
          "* [",
          okf_link_text(concept$title),
          "](",
          basename(concept$path),
          ")",
          description
        )
      },
      character(1)
    )
    okf_write_text(
      file.path(
        stage,
        "concepts",
        utils::URLencode(class, reserved = TRUE),
        "index.md"
      ),
      paste(
        c(paste0("# ", okf_heading_text(class)), "", entries, ""),
        collapse = "\n"
      )
    )
  }
  bundle_digest <- okf_bundle_digest(stage)
  index_frontmatter$graft$bundle_digest <- bundle_digest
  okf_write_text(
    file.path(stage, "index.md"),
    okf_document(index_frontmatter, paste(body, collapse = "\n"))
  )
  bundle_digest
}

okf_bundle_digest <- function(path) {
  root_link <- Sys.readlink(path)
  if (!is.na(root_link) && nzchar(root_link)) {
    abort_backend_error(
      "Symbolic links are not supported in managed OKF bundles.",
      operation = "okf_bundle_files",
      path = path
    )
  }
  root <- normalizePath(path, winslash = "/", mustWork = TRUE)
  files <- okf_bundle_entries(root, include_directories = FALSE)
  relative <- substring(
    normalizePath(files, winslash = "/", mustWork = TRUE),
    nchar(root) + 2L
  )
  order <- order(relative, method = "radix")
  files <- files[order]
  relative <- relative[order]
  entries <- vapply(
    seq_along(files),
    function(index) {
      content_digest <- if (identical(relative[[index]], "index.md")) {
        lines <- readLines(
          files[[index]],
          warn = FALSE,
          encoding = "UTF-8"
        )
        lines <- lines[
          !grepl("^[[:space:]]+bundle_digest:", lines)
        ]
        digest::digest(
          paste0(paste(lines, collapse = "\n"), "\n"),
          algo = "sha256",
          serialize = FALSE
        )
      } else {
        digest::digest(
          files[[index]],
          algo = "sha256",
          file = TRUE,
          serialize = FALSE
        )
      }
      paste0(
        relative[[index]],
        "\n",
        content_digest
      )
    },
    character(1)
  )
  paste0(
    "sha256:",
    digest::digest(
      paste(entries, collapse = "\n"),
      algo = "sha256",
      serialize = FALSE
    )
  )
}

okf_bundle_entries <- function(path, include_directories = FALSE) {
  root_link <- Sys.readlink(path)
  if (!is.na(root_link) && nzchar(root_link)) {
    abort_backend_error(
      "Symbolic links are not supported in managed OKF bundles.",
      operation = "okf_bundle_files",
      path = path
    )
  }
  entries <- list.files(
    path,
    recursive = TRUE,
    full.names = TRUE,
    all.files = TRUE,
    no.. = TRUE,
    include.dirs = TRUE
  )
  if (length(entries) == 0L) {
    return(character())
  }
  links <- Sys.readlink(entries)
  if (any(!is.na(links) & nzchar(links))) {
    abort_backend_error(
      "Symbolic links are not supported in managed OKF bundles.",
      operation = "okf_bundle_files",
      path = entries[which(!is.na(links) & nzchar(links))[[1L]]]
    )
  }
  info <- file.info(entries)
  if (anyNA(info$isdir)) {
    abort_backend_error(
      "An OKF bundle entry could not be inspected.",
      operation = "okf_bundle_files",
      path = entries[which(is.na(info$isdir))[[1L]]]
    )
  }
  if (include_directories) {
    entries
  } else {
    entries[!info$isdir]
  }
}

okf_write_text <- function(path, text) {
  connection <- file(path, open = "wb")
  on.exit(close(connection), add = TRUE)
  writeChar(enc2utf8(text), connection, eos = NULL, useBytes = TRUE)
}

okf_validate_staged_bundle <- function(stage, expected_count) {
  index <- okf_parse_frontmatter(file.path(stage, "index.md"))
  if (!identical(as.character(index$okf_version), graft_okf_version)) {
    abort_backend_error(
      "The staged OKF bundle has an invalid version marker.",
      operation = "export_okf_validate",
      path = stage
    )
  }
  files <- list.files(
    stage,
    pattern = "\\.md$",
    recursive = TRUE,
    full.names = TRUE,
    all.files = TRUE,
    no.. = TRUE
  )
  files <- files[!basename(files) %in% c("index.md", "log.md")]
  if (length(files) != expected_count) {
    abort_backend_error(
      "The staged OKF bundle has an unexpected concept count.",
      operation = "export_okf_validate",
      expected_count = expected_count,
      observed_count = length(files)
    )
  }
  for (path in files) {
    frontmatter <- okf_parse_frontmatter(path)
    if (is.null(okf_scalar_text(frontmatter$type))) {
      abort_backend_error(
        "A staged OKF concept does not declare a non-empty type.",
        operation = "export_okf_validate",
        path = path
      )
    }
  }
  invisible(stage)
}

okf_parse_frontmatter <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  delimiters <- which(lines == "---")
  if (
    length(delimiters) < 2L ||
      delimiters[[1L]] != 1L ||
      delimiters[[2L]] <= 2L
  ) {
    abort_backend_error(
      "An OKF document has malformed YAML frontmatter.",
      operation = "export_okf_validate",
      path = path
    )
  }
  text <- paste(
    lines[seq.int(delimiters[[1L]] + 1L, delimiters[[2L]] - 1L)],
    collapse = "\n"
  )
  value <- tryCatch(
    yaml::yaml.load(text, eval.expr = FALSE),
    error = function(error) {
      abort_backend_error(
        "An OKF document has invalid YAML frontmatter.",
        operation = "export_okf_validate",
        path = path,
        parent = error
      )
    }
  )
  if (!is.list(value) || is.null(names(value))) {
    abort_backend_error(
      "OKF frontmatter must be a YAML mapping.",
      operation = "export_okf_validate",
      path = path
    )
  }
  value
}

okf_check_destination <- function(path, overwrite) {
  if (!file.exists(path) && !dir.exists(path)) {
    return(invisible(path))
  }
  if (!dir.exists(path)) {
    abort_backend_error(
      "The OKF destination exists and is not a directory.",
      operation = "export_okf",
      path = path
    )
  }
  if (!overwrite) {
    abort_backend_error(
      paste0(
        "The OKF destination `",
        path,
        "` already exists; set `overwrite = TRUE` to replace a Graft bundle."
      ),
      operation = "export_okf",
      path = path
    )
  }
  if (nzchar(Sys.readlink(path)) || !okf_is_graft_bundle(path)) {
    abort_backend_error(
      "Only an existing Graft-produced OKF bundle may be overwritten.",
      operation = "export_okf",
      path = path
    )
  }
  invisible(path)
}

okf_is_graft_bundle <- function(path) {
  index <- file.path(path, "index.md")
  if (!file.exists(index)) {
    return(FALSE)
  }
  frontmatter <- tryCatch(okf_parse_frontmatter(index), error = \(...) NULL)
  !is.null(frontmatter) &&
    is.list(frontmatter$graft) &&
    identical(okf_default(frontmatter$graft$profile, NULL), "graft-okf")
}

okf_install_staged_bundle <- function(stage, path, overwrite) {
  if (!dir.exists(path)) {
    if (!file.rename(stage, path)) {
      abort_backend_error(
        "Could not install the staged OKF bundle.",
        operation = "export_okf",
        path = path
      )
    }
    return(invisible(path))
  }

  stopifnot(overwrite, okf_is_graft_bundle(path))
  backup <- tempfile(
    pattern = paste0(".", basename(path), "-backup-"),
    tmpdir = dirname(path)
  )
  if (!file.rename(path, backup)) {
    abort_backend_error(
      "Could not stage the existing OKF bundle for replacement.",
      operation = "export_okf",
      path = path
    )
  }
  installed <- file.rename(stage, path)
  if (!installed) {
    file.rename(backup, path)
    abort_backend_error(
      "Could not install the replacement OKF bundle.",
      operation = "export_okf",
      path = path
    )
  }
  unlink(backup, recursive = TRUE, force = TRUE)
  invisible(path)
}

okf_snapshot_latest_time <- function(snapshot, boundary) {
  if (!is.null(boundary$committed_at)) {
    return(okf_datetime(boundary$committed_at))
  }
  if (length(snapshot) == 0L) {
    return(NULL)
  }
  values <- vapply(
    snapshot,
    \(.x) as.numeric(.x$metadata$committed_at[[1L]]),
    numeric(1)
  )
  okf_datetime(as.POSIXct(max(values), origin = "1970-01-01", tz = "UTC"))
}
