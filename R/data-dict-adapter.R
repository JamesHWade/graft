data_dict_adapter_version <- "0.1.0"
data_dict_export_format_version <- "0.1.0"
data_dict_adapter_digest_cache <- new.env(parent = emptyenv())

compile_data_dict_manifest <- function(
  dictionary,
  source,
  provider,
  output = NULL
) {
  error_call <- rlang::caller_call()
  dictionary <- normalize_json_signed_zero(dictionary)
  data_dict_validate_root(dictionary)
  source <- data_dict_source_metadata(source, dictionary)
  expected_source <- data_dict_manifest_source(
    dictionary,
    source$content_digest
  )
  if (!identical(source, expected_source)) {
    data_dict_abort(
      paste(
        "Data-dict source identity must be derived from the document name",
        "and version."
      ),
      field = "source",
      rule = "source_identity",
      expected_value = expected_source,
      observed_value = source
    )
  }
  source <- expected_source
  provider <- data_dict_provider_metadata(provider, dictionary)
  output <- data_dict_output_path(output)

  compiled <- data_dict_compile_tables(dictionary, source)
  source_digest <- data_dict_manifest_source_digest(
    data_dict_public_document(dictionary),
    source
  )
  source_file <- list(
    schema_id = source$id,
    name = source$name,
    version = source$version,
    content_digest = source$content_digest,
    root = TRUE
  )
  compiler <- list(
    name = "graft-data-dict-adapter",
    version = data_dict_adapter_version,
    script_digest = data_dict_adapter_script_digest(),
    provider = provider
  )
  manifest <- list(
    manifest_version = graft_manifest_version,
    projection_mapping_version = graft_projection_mapping_version,
    schema = list(
      id = source$id,
      name = source$name,
      version = source$version,
      source_files = list(source_file)
    ),
    classes = compiled$classes,
    slots = compiled$slots,
    enums = compiled$enums,
    relations = compiled$relations,
    graph_projections = data_dict_graph_projections(
      compiled$classes,
      compiled$relations
    ),
    validation_invariants = list(),
    identifier_normalization_versions = stats::setNames(
      list(),
      character()
    ),
    compiler = compiler,
    fingerprints = list(
      structural_digest = NULL,
      source_digest = source_digest
    ),
    dictionary = data_dict_dictionary_contract(
      dictionary,
      provider,
      compiled
    )
  )
  manifest$fingerprints$structural_digest <- manifest_structural_digest(
    manifest
  )
  manifest$fingerprints$build_digest <- manifest_build_digest(manifest)

  validate_manifest_header(manifest, "<data-dict export-spec>")
  schema <- new_compiled_schema(manifest, output)
  validate_manifest_integrity(schema)

  if (is.null(output)) {
    return(schema)
  }
  stage <- tempfile(
    pattern = paste0(".", basename(output), "-stage-"),
    tmpdir = dirname(output),
    fileext = ".graft.json"
  )
  on.exit(unlink(stage, force = TRUE), add = TRUE)
  writeLines(canonical_json(manifest), stage, useBytes = TRUE)
  loaded <- load_schema_manifest(stage)
  validate_manifest_integrity(loaded)
  new_graft_schema(loaded)
  install_compiled_manifest(stage, output, call = error_call)
  loaded$path <- normalizePath(output, winslash = "/", mustWork = TRUE)
  loaded
}

data_dict_adapter_script_digest <- function() {
  namespace <- environment(compile_data_dict_manifest)
  namespace_bindings <- mget(
    ls(namespace, all.names = TRUE),
    envir = namespace,
    inherits = FALSE
  )
  functions <- Filter(is.function, namespace_bindings)
  functions <- functions[order(names(functions), method = "radix")]
  versions <- list(
    adapter_version = data_dict_adapter_version,
    export_format_version = data_dict_export_format_version,
    manifest_version = graft_manifest_version,
    projection_mapping_version = graft_projection_mapping_version
  )
  cache_key <- list(functions = functions, versions = versions)
  if (
    exists("key", envir = data_dict_adapter_digest_cache, inherits = FALSE) &&
      identical(data_dict_adapter_digest_cache$key, cache_key)
  ) {
    return(data_dict_adapter_digest_cache$digest)
  }
  source <- lapply(
    functions,
    \(fn) {
      list(
        formals = paste(
          deparse(formals(fn), width.cutoff = 500L),
          collapse = "\n"
        ),
        body = paste(
          deparse(body(fn), width.cutoff = 500L),
          collapse = "\n"
        )
      )
    }
  )
  result <- graft_sha256(canonical_json(c(
    versions,
    list(functions = source)
  )))
  data_dict_adapter_digest_cache$key <- cache_key
  data_dict_adapter_digest_cache$digest <- result
  result
}

data_dict_validate_root <- function(dictionary) {
  if (!is.list(dictionary) || is.object(dictionary)) {
    data_dict_abort(
      "`dictionary` must be a resolved data-dict export-spec object.",
      field = "dictionary",
      rule = "resolved_export_spec"
    )
  }
  data_dict_reject_duplicate_json_keys(dictionary)
  version <- dictionary[["$version"]]
  if (!data_dict_is_string(version)) {
    data_dict_abort(
      "The resolved data-dict export must declare `$version`.",
      field = "$version",
      rule = "export_format_version"
    )
  }
  if (!identical(version, data_dict_export_format_version)) {
    data_dict_abort(
      paste0("Unsupported data-dict export-spec version `", version, "`."),
      field = "$version",
      rule = "export_format_version",
      observed_value = version,
      supported_value = data_dict_export_format_version
    )
  }
  if (
    !data_dict_is_array(dictionary$tables) ||
      length(dictionary$tables) == 0L
  ) {
    data_dict_abort(
      "The resolved data-dict export must contain at least one table.",
      field = "tables",
      rule = "nonempty_tables"
    )
  }
  if (!data_dict_is_string(dictionary$name)) {
    data_dict_abort(
      "A data-dict used as a Graft contract must declare `name`.",
      field = "name",
      rule = "graft_contract_name"
    )
  }
  data_dict_reject_export_data(dictionary)
  data_dict_reject_unsafe_json_numbers(dictionary)
  invisible(dictionary)
}

data_dict_reject_duplicate_json_keys <- function(value, path = NULL) {
  duplicate <- duplicate_json_object_key(value)
  if (!is.null(duplicate)) {
    data_dict_abort(
      paste0(
        "The resolved data-dict contains duplicate JSON object key `",
        duplicate$key,
        "`."
      ),
      field = duplicate$path,
      rule = "duplicate_json_key",
      schema_path = path
    )
  }
  invisible(value)
}

data_dict_reject_unsafe_json_numbers <- function(value, path = "$") {
  if (is.numeric(value)) {
    unsafe <- !is.finite(value) | abs(value) > 2^53 - 1
    if (any(unsafe)) {
      data_dict_abort(
        paste(
          "The resolved data-dict contains a numeric value outside R's exact",
          "integer range; use a quoted string contract instead."
        ),
        field = path,
        rule = "unsafe_json_number"
      )
    }
    return(invisible(value))
  }
  if (!is.list(value)) {
    return(invisible(value))
  }
  value_names <- names(value)
  for (index in seq_along(value)) {
    name <- if (
      !is.null(value_names) &&
        length(value_names) >= index &&
        nzchar(value_names[[index]])
    ) {
      value_names[[index]]
    } else {
      NULL
    }
    child_path <- if (is.null(name)) {
      paste0(path, "[", index, "]")
    } else if (identical(path, "$")) {
      paste0(path, ".", name)
    } else {
      paste(path, name, sep = ".")
    }
    data_dict_reject_unsafe_json_numbers(value[[index]], child_path)
  }
  invisible(value)
}

data_dict_reject_export_data <- function(dictionary) {
  for (table_index in seq_along(dictionary$tables)) {
    table <- dictionary$tables[[table_index]]
    table_path <- paste0("tables[", table_index, "]")
    if (is.list(table) && "rows" %in% names(table)) {
      data_dict_abort(
        "Graft contracts require export-spec JSON, not profiled export-data.",
        field = paste0(table_path, ".rows"),
        rule = "export_spec_only"
      )
    }
    if (!is.list(table) || !is.list(table$columns)) {
      next
    }
    for (column_index in seq_along(table$columns)) {
      data_dict_reject_column_profile(
        table$columns[[column_index]],
        paste0(table_path, ".columns[", column_index, "]")
      )
    }
  }
  invisible(dictionary)
}

data_dict_reject_column_profile <- function(column, path) {
  if (!is.list(column)) {
    return(invisible(column))
  }
  if ("profile" %in% names(column)) {
    data_dict_abort(
      "Graft contracts require export-spec JSON, not profiled export-data.",
      field = paste0(path, ".profile"),
      rule = "export_spec_only"
    )
  }
  if (is.list(column$fields)) {
    for (field_index in seq_along(column$fields)) {
      data_dict_reject_column_profile(
        column$fields[[field_index]],
        paste0(path, ".fields[", field_index, "]")
      )
    }
  }
  invisible(column)
}

data_dict_source_metadata <- function(source, dictionary) {
  if (!is.list(source) || is.object(source)) {
    data_dict_abort(
      "`source` must be a metadata object.",
      field = "source",
      rule = "source_metadata"
    )
  }
  allowed <- c("id", "name", "version", "content_digest")
  unexpected <- setdiff(names(source), allowed)
  if (length(unexpected) > 0L) {
    data_dict_abort(
      "`source` contains unsupported metadata fields.",
      field = "source",
      rule = "source_metadata",
      unexpected_fields = unexpected
    )
  }
  for (field in c("id", "name")) {
    if (!data_dict_is_string(source[[field]])) {
      data_dict_abort(
        paste0("`source$", field, "` must be one non-empty string."),
        field = paste0("source.", field),
        rule = "source_metadata"
      )
    }
  }
  version <- source$version
  if (!is.null(version) && !data_dict_is_string(version)) {
    data_dict_abort(
      "`source$version` must be `NULL` or one non-empty string.",
      field = "source.version",
      rule = "source_metadata"
    )
  }
  content_digest <- source$content_digest
  if (is.null(content_digest)) {
    content_digest <- graft_sha256(canonical_json(dictionary))
  } else if (!is_graft_digest(content_digest)) {
    data_dict_abort(
      "`source$content_digest` must be a canonical SHA-256 digest.",
      field = "source.content_digest",
      rule = "source_metadata",
      observed_value = content_digest
    )
  }
  list(
    id = source$id,
    name = source$name,
    version = version,
    content_digest = content_digest
  )
}

data_dict_provider_metadata <- function(provider, dictionary) {
  if (!is.list(provider) || is.object(provider)) {
    data_dict_abort(
      "`provider` must be a metadata object.",
      field = "provider",
      rule = "provider_metadata"
    )
  }
  public_fields <- c(
    "name",
    "export_format_version",
    "source_spec_version",
    "cli_version",
    "cli_digest",
    "revision",
    "source_format"
  )
  allowed_fields <- c(public_fields, "source_path")
  unexpected <- setdiff(names(provider), allowed_fields)
  if (
    is.null(names(provider)) ||
      anyDuplicated(names(provider)) ||
      length(unexpected) > 0L
  ) {
    data_dict_abort(
      "`provider` contains unsupported or duplicate metadata fields.",
      field = "provider",
      rule = "provider_metadata",
      unexpected_fields = unexpected
    )
  }
  for (field in c("name", "export_format_version")) {
    if (!data_dict_is_string(provider[[field]])) {
      data_dict_abort(
        paste0("`provider$", field, "` must be one non-empty string."),
        field = paste0("provider.", field),
        rule = "provider_metadata"
      )
    }
  }
  if (!identical(provider$name, "data-dict")) {
    data_dict_abort(
      "`provider$name` must be `data-dict`.",
      field = "provider.name",
      rule = "provider_metadata",
      observed_value = provider$name
    )
  }
  if (
    !identical(
      provider$export_format_version,
      dictionary[["$version"]]
    )
  ) {
    data_dict_abort(
      paste0(
        "`provider$export_format_version` must match the resolved export ",
        "`$version`."
      ),
      field = "provider.export_format_version",
      rule = "provider_export_format_version",
      observed_value = provider$export_format_version,
      expected_value = dictionary[["$version"]]
    )
  }
  if (is.null(provider$source_format)) {
    provider$source_format <- "resolved_json"
  }
  for (field in c("source_spec_version", "cli_version", "revision")) {
    if (
      !is.null(provider[[field]]) && !data_dict_is_string(provider[[field]])
    ) {
      data_dict_abort(
        paste0(
          "`provider$",
          field,
          "` must be `NULL` or one non-empty string."
        ),
        field = paste0("provider.", field),
        rule = "provider_metadata"
      )
    }
  }
  if (!is.null(provider$cli_digest) && !is_graft_digest(provider$cli_digest)) {
    data_dict_abort(
      "`provider$cli_digest` must be `NULL` or a canonical SHA-256 digest.",
      field = "provider.cli_digest",
      rule = "provider_metadata"
    )
  }
  if (
    !data_dict_is_string(provider$source_format) ||
      !provider$source_format %in% c("yaml", "resolved_json")
  ) {
    data_dict_abort(
      "`provider$source_format` must be `yaml` or `resolved_json`.",
      field = "provider.source_format",
      rule = "provider_metadata",
      observed_value = provider$source_format
    )
  }
  if (
    !is.null(provider$source_path) && !data_dict_is_string(provider$source_path)
  ) {
    data_dict_abort(
      "`provider$source_path` must be `NULL` or one non-empty string.",
      field = "provider.source_path",
      rule = "provider_metadata"
    )
  }
  yaml_provider <- identical(provider$source_format, "yaml") &&
    data_dict_is_string(provider$source_spec_version) &&
    data_dict_is_string(provider$cli_version) &&
    is_graft_digest(provider$cli_digest)
  resolved_provider <- identical(provider$source_format, "resolved_json") &&
    is.null(provider$source_spec_version) &&
    is.null(provider$cli_version) &&
    is.null(provider$cli_digest)
  if (!yaml_provider && !resolved_provider) {
    data_dict_abort(
      "`provider` metadata is inconsistent with its source format.",
      field = "provider",
      rule = "provider_source_format"
    )
  }
  provider[intersect(public_fields, names(provider))]
}

compile_data_dict_source <- function(path, output) {
  contract <- read_data_dict_contract(path)
  source <- data_dict_manifest_source(
    contract$document,
    contract$source_digest
  )
  compile_data_dict_manifest(
    dictionary = contract$document,
    source = source,
    provider = contract$provider,
    output = output
  )
}

data_dict_manifest_source <- function(dictionary, content_digest) {
  name <- dictionary$name
  if (!data_dict_is_string(name)) {
    data_dict_abort(
      "A data-dict used as a Graft contract must declare `name`.",
      field = "name",
      rule = "graft_contract_name"
    )
  }
  if (!is_graft_digest(content_digest)) {
    data_dict_abort(
      "The captured data-dict source digest is invalid.",
      field = "source.content_digest",
      rule = "source_digest",
      observed_value = content_digest
    )
  }
  list(
    id = paste0("urn:data-dict:", utils::URLencode(name, reserved = TRUE)),
    name = name,
    version = data_dict_document_version(dictionary$version),
    content_digest = content_digest
  )
}

data_dict_manifest_source_digest <- function(dictionary, source) {
  graft_sha256(canonical_json(list(
    dictionary = dictionary,
    source = source
  )))
}

data_dict_document_version <- function(version) {
  if (is.null(version)) {
    return(NULL)
  }
  allowed <- c("number", "date", "hash")
  if (
    !is.list(version) ||
      is.null(names(version)) ||
      length(version) != 1L ||
      !names(version)[[1L]] %in% allowed ||
      !data_dict_is_string(version[[1L]])
  ) {
    data_dict_abort(
      paste(
        "Resolved data-dict `version` must be an object containing exactly",
        "one scalar string field named number, date, or hash."
      ),
      field = "version",
      rule = "data_version"
    )
  }
  kind <- names(version)[[1L]]
  value <- version[[1L]]
  if (
    identical(kind, "number") &&
      !grepl(
        paste0(
          "^[0-9]+\\.[0-9]+\\.[0-9]+",
          "(?:-[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*)?",
          "(?:\\+[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*)?$"
        ),
        value,
        perl = TRUE
      )
  ) {
    data_dict_abort(
      paste(
        "Resolved data-dict `version$number` must have three",
        "dot-separated numeric components with optional pre-release or",
        "build suffixes."
      ),
      field = "version.number",
      rule = "data_version",
      observed_value = value
    )
  }
  if (identical(kind, "date")) {
    parsed <- suppressWarnings(as.Date(value, format = "%Y-%m-%d"))
    valid <- grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", value) &&
      !is.na(parsed) &&
      identical(format(parsed, "%Y-%m-%d"), value)
    if (!valid) {
      data_dict_abort(
        "Resolved data-dict `version$date` must be a valid ISO 8601 date.",
        field = "version.date",
        rule = "data_version",
        observed_value = value
      )
    }
  }
  value
}

data_dict_output_path <- function(output) {
  if (is.null(output)) {
    return(NULL)
  }
  if (!data_dict_is_string(output)) {
    data_dict_abort(
      "`output` must be `NULL` or one non-empty path.",
      field = "output",
      rule = "output_path"
    )
  }
  directory <- dirname(output)
  if (!dir.exists(directory)) {
    data_dict_abort(
      paste0("Output directory does not exist: `", directory, "`."),
      field = "output",
      rule = "output_directory",
      observed_value = output
    )
  }
  normalizePath(output, winslash = "/", mustWork = FALSE)
}

data_dict_compile_tables <- function(dictionary, source) {
  tables <- dictionary$tables
  table_names <- vapply(
    seq_along(tables),
    \(index) data_dict_table_name(tables[[index]], index),
    character(1)
  )
  if (anyDuplicated(table_names)) {
    data_dict_abort(
      "Table names must be unique.",
      field = "tables",
      rule = "unique_table_names",
      observed_value = table_names
    )
  }
  table_views <- vapply(table_names, projection_snake_case, character(1))
  if (
    !all(nzchar(table_views)) ||
      any(startsWith(table_views, "_graft_")) ||
      anyDuplicated(tolower(table_views))
  ) {
    data_dict_abort(
      "Table names must produce valid, unique Graft projection names.",
      field = "tables",
      rule = "unique_projection_names",
      observed_value = table_views
    )
  }

  identities <- vector("list", length(tables))
  names(identities) <- table_names
  column_names <- vector("list", length(tables))
  names(column_names) <- table_names
  for (index in seq_along(tables)) {
    table <- tables[[index]]
    path <- paste0("tables[", index, "]")
    columns <- table$columns
    if (!data_dict_is_array(columns) || length(columns) == 0L) {
      data_dict_abort(
        paste0("Table `", table_names[[index]], "` must contain columns."),
        field = paste0(path, ".columns"),
        rule = "nonempty_columns"
      )
    }
    names_for_table <- vapply(
      seq_along(columns),
      \(column_index) {
        data_dict_column_name(
          columns[[column_index]],
          path,
          column_index
        )
      },
      character(1)
    )
    if (anyDuplicated(names_for_table)) {
      data_dict_abort(
        paste0(
          "Column names for table `",
          table_names[[index]],
          "` must be unique."
        ),
        field = paste0(path, ".columns"),
        rule = "unique_column_names",
        observed_value = names_for_table
      )
    }
    views <- vapply(names_for_table, projection_snake_case, character(1))
    if (!all(nzchar(views)) || anyDuplicated(tolower(views))) {
      data_dict_abort(
        paste0(
          "Columns for table `",
          table_names[[index]],
          "` must produce unique projection names."
        ),
        field = paste0(path, ".columns"),
        rule = "unique_projection_columns",
        observed_value = views
      )
    }
    primary <- which(vapply(
      seq_along(columns),
      \(column_index) {
        "primary_key" %in%
          data_dict_constraints(
            columns[[column_index]],
            paste0(path, ".columns[", column_index, "]")
          )
      },
      logical(1)
    ))
    if (length(primary) != 1L) {
      data_dict_abort(
        paste0(
          "Table `",
          table_names[[index]],
          "` must declare exactly one primary key."
        ),
        field = paste0(path, ".columns"),
        rule = "unambiguous_identity",
        observed_value = names_for_table[primary]
      )
    }
    if (!identical(names_for_table[[primary]], "id")) {
      data_dict_abort(
        paste0(
          "The primary key for table `",
          table_names[[index]],
          "` must be named `id`."
        ),
        field = paste0(path, ".columns[", primary, "].name"),
        rule = "primary_id",
        observed_value = names_for_table[[primary]]
      )
    }
    identities[[table_names[[index]]]] <- list(
      column = "id",
      index = primary,
      type = columns[[primary]]$type
    )
    column_names[[table_names[[index]]]] <- names_for_table
  }
  contract_keys <- unlist(
    Map(
      \(table_name, names_for_table) {
        paste(table_name, names_for_table, sep = ".")
      },
      names(column_names),
      column_names
    ),
    use.names = FALSE
  )
  duplicated_keys <- unique(contract_keys[
    duplicated(contract_keys) | duplicated(contract_keys, fromLast = TRUE)
  ])
  if (length(duplicated_keys) > 0L) {
    data_dict_abort(
      paste0(
        "Table and column names produce ambiguous Graft contract keys: ",
        paste(duplicated_keys, collapse = ", "),
        "."
      ),
      field = "tables",
      rule = "ambiguous_contract_keys",
      observed_value = duplicated_keys
    )
  }

  classes <- stats::setNames(list(), character())
  slots <- stats::setNames(list(), character())
  enums <- stats::setNames(list(), character())
  relations <- list()
  for (index in seq_along(tables)) {
    result <- data_dict_compile_table(
      table = tables[[index]],
      table_index = index,
      table_name = table_names[[index]],
      table_view = table_views[[index]],
      table_names = table_names,
      identities = identities,
      column_names = column_names,
      source = source
    )
    classes[[table_names[[index]]]] <- result$class
    for (slot_name in names(result$class$slots)) {
      slots[[paste(table_names[[index]], slot_name, sep = ".")]] <-
        data_dict_global_slot(result$class$slots[[slot_name]])
    }
    if (length(result$enums) > 0L) {
      enums <- c(enums, result$enums)
    }
    relations <- c(relations, result$relations)
  }
  relations <- relations[order(
    vapply(relations, \(relation) relation$name, character(1)),
    method = "radix"
  )]
  list(classes = classes, slots = slots, enums = enums, relations = relations)
}

data_dict_compile_table <- function(
  table,
  table_index,
  table_name,
  table_view,
  table_names,
  identities,
  column_names,
  source
) {
  columns <- table$columns
  path <- paste0("tables[", table_index, "]")
  slots <- stats::setNames(list(), character())
  enums <- stats::setNames(list(), character())
  relations <- list()
  for (column_index in seq_along(columns)) {
    column <- columns[[column_index]]
    column_name <- column_names[[table_name]][[column_index]]
    column_path <- paste0(path, ".columns[", column_index, "]")
    compiled <- data_dict_compile_column(
      column,
      column_name,
      column_path,
      table_name,
      table_view,
      table_names,
      identities
    )
    slots[[column_name]] <- compiled$slot
    if (!is.null(compiled$enum)) {
      enums[[compiled$enum$name]] <- compiled$enum
    }
    if (!is.null(compiled$relation)) {
      relations[[length(relations) + 1L]] <- compiled$relation
    }
  }
  candidates <- names(Filter(
    \(slot) {
      !slot$identifier &&
        !slot$multivalued &&
        !slot$object_reference &&
        !slot$sensitive &&
        identical(slot$duckdb_type, "VARCHAR")
    },
    slots
  ))
  preferred <- intersect(c("label", "title", "name", "description"), candidates)
  label_slot <- if (length(preferred) > 0L) {
    preferred[[1L]]
  } else if (length(candidates) > 0L) {
    candidates[[1L]]
  } else {
    NULL
  }
  class_relations <- as.list(sort(
    vapply(relations, \(relation) relation$name, character(1)),
    method = "radix"
  ))
  class <- list(
    name = table_name,
    is_a = NULL,
    ancestors = list(),
    type_uri = paste0(
      source$id,
      "#",
      utils::URLencode(table_name, reserved = TRUE)
    ),
    role = "node",
    statement_shape = NULL,
    view = table_view,
    id_policy = "require",
    id_format = "linkml",
    label_slot = label_slot,
    search_slots = as.list(sort(candidates, method = "radix")),
    origin_key_slots = list(),
    qualifier_slots = list(),
    fixed_predicate = NULL,
    slots = slots,
    relations = class_relations
  )
  list(class = class, enums = enums, relations = relations)
}

data_dict_compile_column <- function(
  column,
  column_name,
  path,
  table_name,
  table_view,
  table_names,
  identities
) {
  if ("fields" %in% names(column)) {
    data_dict_abort(
      "Nested column fields are not supported by the graft-table-v1 profile.",
      field = paste0(path, ".fields"),
      rule = "unsupported_nested_fields"
    )
  }
  type <- column$type
  if (!data_dict_is_string(type)) {
    data_dict_abort(
      "Each column must have one resolved canonical type.",
      field = paste0(path, ".type"),
      rule = "canonical_column_type"
    )
  }
  parsed <- data_dict_parse_type(type, paste0(path, ".type"))
  time_zone <- column$time_zone
  if (!is.null(time_zone)) {
    if (
      !identical(parsed$base, "datetime") ||
        !data_dict_is_string(time_zone) ||
        !identical(time_zone, "UTC")
    ) {
      data_dict_abort(
        "The graft-table-v1 profile supports only `time_zone: UTC`.",
        field = paste0(path, ".time_zone"),
        rule = "datetime_time_zone",
        observed_value = time_zone,
        supported_value = "UTC"
      )
    }
  }
  datetime_format <- if (!identical(parsed$base, "datetime")) {
    NULL
  } else if (is.null(time_zone)) {
    "offset"
  } else {
    "local_utc"
  }
  display <- data_dict_display(column, path)
  constraints <- data_dict_constraints(column, path)
  identifier <- "primary_key" %in% constraints
  if (
    identifier &&
      (parsed$multivalued || !identical(parsed$base, "string"))
  ) {
    data_dict_abort(
      "A primary `id` must use scalar type `string`.",
      field = paste0(path, ".type"),
      rule = "primary_id_type",
      observed_value = type
    )
  }
  if (identifier && identical(display, "restricted")) {
    data_dict_abort(
      "A primary `id` cannot use `display: restricted` in Graft.",
      field = paste0(path, ".display"),
      rule = "public_identifier"
    )
  }
  reference <- column$references
  if (
    identifier &&
      ("foreign_key" %in% constraints || !is.null(reference))
  ) {
    data_dict_abort(
      paste(
        "A primary `id` cannot also be a foreign key because Graft IDs are",
        "globally unique across tables."
      ),
      field = paste0(path, ".constraints"),
      rule = "primary_foreign_key"
    )
  }
  if ("foreign_key" %in% constraints && is.null(reference)) {
    data_dict_abort(
      "A foreign-key column must include resolved `references` metadata.",
      field = paste0(path, ".references"),
      rule = "resolved_foreign_key"
    )
  }
  if (!is.null(reference) && !"foreign_key" %in% constraints) {
    data_dict_abort(
      "Resolved `references` metadata requires a `foreign_key` constraint.",
      field = paste0(path, ".references"),
      rule = "resolved_foreign_key"
    )
  }
  object_reference <- "foreign_key" %in% constraints
  target_class <- NULL
  if (object_reference) {
    if (parsed$multivalued) {
      data_dict_abort(
        "A list column cannot be used as a foreign key.",
        field = paste0(path, ".references"),
        rule = "scalar_foreign_key"
      )
    }
    if (!identical(parsed$base, "string")) {
      data_dict_abort(
        "A foreign key must use scalar type `string` in Graft.",
        field = paste0(path, ".type"),
        rule = "foreign_key_type",
        observed_value = type
      )
    }
    if (
      !is.list(reference) ||
        is.object(reference) ||
        is.null(names(reference)) ||
        anyDuplicated(names(reference)) ||
        !setequal(names(reference), c("table", "column")) ||
        !data_dict_is_string(reference$table) ||
        !data_dict_is_string(reference$column)
    ) {
      data_dict_abort(
        "`references` must resolve to one table and column.",
        field = paste0(path, ".references"),
        rule = "resolved_foreign_key"
      )
    }
    if (!(reference$table %in% table_names)) {
      data_dict_abort(
        paste0(
          "Foreign key target table `",
          reference$table,
          "` does not exist."
        ),
        field = paste0(path, ".references.table"),
        rule = "foreign_key_target",
        observed_value = reference$table
      )
    }
    if (!identical(reference$column, identities[[reference$table]]$column)) {
      data_dict_abort(
        "Foreign keys must reference the target table's primary `id`.",
        field = paste0(path, ".references.column"),
        rule = "foreign_key_identity",
        observed_value = reference$column
      )
    }
    target_class <- reference$table
  }

  enum <- NULL
  enum_name <- NULL
  if (identical(parsed$base, "enum")) {
    enum_name <- paste(table_name, column_name, "enum", sep = ".")
    enum <- data_dict_enum_contract(
      enum_name,
      column$values,
      paste0(path, ".values")
    )
  }
  primitive <- data_dict_primitive_contract(parsed$base, path)
  range <- if (object_reference) {
    target_class
  } else if (!is.null(enum_name)) {
    enum_name
  } else {
    primitive$range
  }
  duckdb_type <- if (object_reference) "VARCHAR" else primitive$duckdb_type
  slot <- list(
    name = column_name,
    view_column = if (parsed$multivalued) {
      NULL
    } else {
      projection_snake_case(column_name)
    },
    range = range,
    duckdb_type = duckdb_type,
    required = identifier || "required" %in% constraints,
    multivalued = parsed$multivalued,
    ordered = parsed$multivalued,
    identifier = identifier,
    object_reference = object_reference,
    enum = enum_name,
    meaning = NULL,
    pattern = NULL,
    datetime_format = datetime_format,
    minimum_value = NULL,
    maximum_value = NULL,
    external_identifier = NULL,
    search_weight = NULL,
    sensitive = identical(display, "restricted")
  )
  relation <- NULL
  if (parsed$multivalued) {
    relation <- list(
      name = paste(table_name, column_name, sep = "."),
      view = paste0(table_view, "__", projection_snake_case(column_name)),
      owner_class = table_name,
      owner_view = table_view,
      slot = column_name,
      kind = if (object_reference) "object" else "value",
      ordered = TRUE,
      predicate = paste0(
        "urn:data-dict:slot:",
        utils::URLencode(table_name, reserved = TRUE),
        ".",
        utils::URLencode(column_name, reserved = TRUE)
      )
    )
  }
  list(slot = slot, enum = enum, relation = relation)
}

data_dict_parse_type <- function(type, field) {
  if (identical(type, "struct") || identical(type, "list(struct)")) {
    data_dict_abort(
      "Struct columns are not supported by the Graft adapter.",
      field = field,
      rule = "unsupported_struct",
      observed_value = type
    )
  }
  if (grepl("^list\\(list\\(", type)) {
    data_dict_abort(
      "Nested list columns are not supported by the Graft adapter.",
      field = field,
      rule = "unsupported_nested_list",
      observed_value = type
    )
  }
  if (startsWith(type, "list(")) {
    if (!endsWith(type, ")")) {
      data_dict_abort(
        "The list element type is not supported by the Graft adapter.",
        field = field,
        rule = "unsupported_list_type",
        observed_value = type
      )
    }
    return(list(
      base = substr(type, 6L, nchar(type) - 1L),
      multivalued = TRUE
    ))
  }
  list(base = type, multivalued = FALSE)
}

data_dict_primitive_contract <- function(type, path) {
  switch(
    type,
    string = list(range = "string", duckdb_type = "VARCHAR"),
    boolean = list(range = "boolean", duckdb_type = "BOOLEAN"),
    date = list(range = "date", duckdb_type = "DATE"),
    datetime = list(range = "datetime", duckdb_type = "TIMESTAMP"),
    enum = list(range = "string", duckdb_type = "VARCHAR"),
    number = list(range = "double", duckdb_type = "DOUBLE"),
    `number(quantity)` = list(range = "double", duckdb_type = "DOUBLE"),
    `number(ordinal)` = list(range = "double", duckdb_type = "DOUBLE"),
    `number(id)` = data_dict_abort(
      paste(
        "The graft-table-v1 profile does not accept number(id); use a",
        "quoted string code to preserve exact identity."
      ),
      field = paste0(path, ".type"),
      rule = "unsupported_number_id",
      observed_value = type
    ),
    data_dict_abort(
      paste0("Unsupported canonical data-dict type `", type, "`."),
      field = paste0(path, ".type"),
      rule = "unsupported_column_type",
      observed_value = type
    )
  )
}

data_dict_enum_contract <- function(name, values, field) {
  if (is.null(values)) {
    data_dict_abort(
      "Enum columns must include resolved `values`.",
      field = field,
      rule = "enum_values"
    )
  }
  if (!data_dict_is_array(values)) {
    data_dict_abort(
      "Enum values must be encoded as an array.",
      field = field,
      rule = "enum_values"
    )
  }
  if (!all(vapply(values, data_dict_is_string, logical(1)))) {
    data_dict_abort(
      "Enum values must be encoded as a flat string array.",
      field = field,
      rule = "enum_values"
    )
  }
  values <- unlist(values, recursive = FALSE, use.names = FALSE)
  if (
    !is.character(values) ||
      length(values) == 0L ||
      anyNA(values) ||
      !all(nzchar(trimws(values))) ||
      anyDuplicated(values)
  ) {
    data_dict_abort(
      "Enum values must be unique strings that are non-empty after trimming.",
      field = field,
      rule = "enum_values",
      observed_value = values
    )
  }
  list(
    name = name,
    description = NULL,
    permissible_values = lapply(
      values,
      \(value) list(value = value, meaning = NULL, description = NULL)
    )
  )
}

data_dict_display <- function(column, path) {
  display <- column$display
  if (is.null(display)) {
    return(NULL)
  }
  if (!data_dict_is_string(display) || !identical(display, "restricted")) {
    data_dict_abort(
      "Column display must be omitted or the scalar string `restricted`.",
      field = paste0(path, ".display"),
      rule = "column_display"
    )
  }
  display
}

data_dict_global_slot <- function(slot) {
  slot[c(
    "name",
    "range",
    "duckdb_type",
    "required",
    "multivalued",
    "identifier",
    "object_reference",
    "enum",
    "meaning",
    "pattern",
    "datetime_format",
    "minimum_value",
    "maximum_value",
    "external_identifier",
    "search_weight",
    "sensitive"
  )]
}

data_dict_graph_projections <- function(classes, relations) {
  object_relations <- vapply(
    Filter(\(relation) identical(relation$kind, "object"), relations),
    \(relation) relation$name,
    character(1)
  )
  list(
    node_classes = as.list(sort(names(classes), method = "radix")),
    semantic_edges = list(
      direct_edge_classes = list(),
      semantic_statement_classes = list(),
      object_relations = as.list(sort(object_relations, method = "radix")),
      exclude_narrative_statements = TRUE
    ),
    provenance_edges = list(
      narrative_statement_classes = list(),
      narrative_slots = as.list(c("about", "primary_subject")),
      statement_to_evidence = TRUE,
      evidence_to_source = TRUE,
      supersession = TRUE,
      mention_resolution = TRUE,
      semantic_derivation = TRUE
    )
  )
}

data_dict_dictionary_contract <- function(dictionary, provider, compiled) {
  column_count <- sum(vapply(
    dictionary$tables,
    \(table) length(table$columns),
    integer(1)
  ))
  object_reference_count <- sum(vapply(
    compiled$classes,
    function(class) {
      sum(vapply(
        class$slots,
        \(slot) isTRUE(slot$object_reference),
        logical(1)
      ))
    },
    integer(1)
  ))
  list(
    provider = unserialize(serialize(provider, NULL)),
    document = data_dict_public_document(dictionary),
    profile = "graft-table-v1",
    defaults = list(
      role = "node",
      id_policy = "require",
      id_format = "linkml"
    ),
    adapter_version = data_dict_adapter_version,
    requirements = as.list(c(
      "a top-level dataset name",
      "one scalar string primary key named id per table",
      "non-empty ids that are globally unique across all tables",
      "flat scalar or single-level list columns",
      "scalar string foreign keys target a table's primary id",
      "names produce non-empty, unique Graft projection and contract keys",
      "primary ids are public operational keys",
      "primary ids are not foreign keys"
    )),
    mapped = list(
      tables_to_classes = length(compiled$classes),
      columns_to_slots = column_count,
      enums = length(compiled$enums),
      foreign_keys_to_object_references = object_reference_count,
      list_columns_to_relations = length(compiled$relations),
      restricted_display_to_sensitive = TRUE
    ),
    preserved = as.list(c(
      "dataset metadata",
      "table metadata",
      "column metadata",
      "relationships",
      "glossary",
      "assertions"
    )),
    not_enforced = list(
      class_inheritance = data_dict_loss(
        "not expressible",
        "All mapped classes use default node semantics."
      ),
      ontology_uris = data_dict_loss(
        "not expressible",
        "Class URIs are synthesized from the source id."
      ),
      graft_role = data_dict_loss(
        "not expressible",
        "Every mapped class uses role node."
      ),
      identity_policy = data_dict_loss(
        "defaulted",
        "Primary id columns use the require policy."
      ),
      identifier_value_semantics = data_dict_loss(
        "stricter in Graft",
        paste(
          "Graft requires primary id values to be non-empty after trimming;",
          "data-dict primary keys require uniqueness and non-null values."
        )
      ),
      requiredness_semantics = data_dict_loss(
        "stricter in Graft",
        paste(
          "Graft treats empty strings and empty lists as missing and rejects",
          "NA list elements; data-dict required constraints govern the",
          "container's nullness."
        )
      ),
      global_identifier_uniqueness = data_dict_loss(
        "stricter in Graft",
        paste(
          "Graft record ids must be unique across every table; data-dict",
          "primary keys are unique within one table, so Graft also rejects",
          "primary-key columns that double as foreign keys."
        )
      ),
      external_identifier_normalization = data_dict_loss(
        "not expressible",
        "No normalization namespace or version is inferred."
      ),
      search_policy = data_dict_loss(
        "inferred",
        "Search uses public scalar text and enum columns."
      ),
      unique_constraints = data_dict_loss(
        "preserved only",
        paste(
          "Non-primary unique constraints remain metadata and are not",
          "enforced by Graft."
        )
      ),
      representative_ranges = data_dict_loss(
        "redacted",
        paste(
          "Observed ranges and examples are excluded from the public",
          "manifest and never become acceptance bounds."
        )
      ),
      assertions = data_dict_loss(
        "preserved only",
        "Assertion source text is not executed by Graft."
      ),
      relationship_cardinality = data_dict_loss(
        "partially mapped",
        paste(
          "Foreign keys map to object references; declared relationship",
          "cardinality remains metadata."
        )
      ),
      relationship_joins = data_dict_loss(
        "preserved only",
        paste(
          "Join text, aliases, conflicts, range joins, and multi-column pairs",
          "remain metadata."
        )
      ),
      graph_relationship_projection = data_dict_loss(
        "not mapped",
        paste(
          "Scalar foreign keys validate references but do not become Graft",
          "graph-edge or traversal relations."
        )
      ),
      profiles = data_dict_loss(
        "not accepted",
        paste(
          "Graft rejects export-data rows and profiles so their observed",
          "values cannot enter through those fields; retained descriptive",
          "metadata remains public and is not content-scrubbed."
        )
      ),
      table_sources = data_dict_loss(
        "redacted",
        paste(
          "Dataset and table origins plus table source locators are excluded",
          "from the public manifest; Graft does not read them or run",
          "data-dict metadata or data validation."
        )
      ),
      datetime_time_zone = data_dict_loss(
        "restricted",
        paste(
          "Only UTC or omitted time zones compile. Omitted zones require",
          "offset-bearing RFC 3339 input; UTC requires zoneless input that",
          "Graft interprets as UTC."
        )
      ),
      measure_semantics = data_dict_loss(
        "preserved only",
        paste(
          "Number measures and units remain metadata; Graft stores supported",
          "numeric types as doubles."
        )
      ),
      number_id_semantics = data_dict_loss(
        "not accepted",
        paste(
          "number(id) can contain integer or floating-point numeric codes that",
          "cannot be lowered to exact text without changing equality; authors",
          "must use quoted string codes."
        )
      ),
      type_validation_semantics = data_dict_loss(
        "mapped",
        paste(
          "Graft validates R candidate values against mapped types, not",
          "against upstream Parquet metadata rules."
        )
      ),
      enum_value_semantics = data_dict_loss(
        "stricter in Graft",
        paste(
          "Graft rejects empty or whitespace-only enum strings because those",
          "scalar values are treated as missing."
        )
      ),
      origin_keys = data_dict_loss(
        "not expressible",
        "No origin-key slots are inferred."
      ),
      qualifier_slots = data_dict_loss(
        "not expressible",
        "No qualifier slots are inferred."
      ),
      polymorphic_references = data_dict_loss(
        "not expressible",
        "Each foreign key must target one concrete table."
      ),
      statement_shape_invariants = data_dict_loss(
        "not expressible",
        "No statement-shape invariants are inferred."
      )
    )
  )
}

data_dict_public_document <- function(dictionary) {
  document <- unserialize(serialize(dictionary, NULL))
  document$origin <- NULL
  for (table_index in seq_along(document$tables)) {
    table <- document$tables[[table_index]]
    table$origin <- NULL
    table$source <- NULL
    for (column_index in seq_along(table$columns)) {
      table$columns[[column_index]] <- data_dict_public_column(
        table$columns[[column_index]]
      )
    }
    document$tables[[table_index]] <- table
  }
  document
}

data_dict_public_column <- function(column) {
  column$examples <- NULL
  column$range <- NULL
  if (is.list(column$fields)) {
    for (field_index in seq_along(column$fields)) {
      column$fields[[field_index]] <- data_dict_public_column(
        column$fields[[field_index]]
      )
    }
  }
  column
}

data_dict_loss <- function(status, handling) {
  list(status = status, handling = handling)
}

data_dict_table_name <- function(table, index) {
  if (!is.list(table) || !data_dict_is_string(table$name)) {
    data_dict_abort(
      "Each table must have one non-empty name.",
      field = paste0("tables[", index, "].name"),
      rule = "table_name"
    )
  }
  table$name
}

data_dict_column_name <- function(column, table_path, index) {
  if (!is.list(column) || !data_dict_is_string(column$name)) {
    data_dict_abort(
      "Each column must have one non-empty name.",
      field = paste0(table_path, ".columns[", index, "].name"),
      rule = "column_name"
    )
  }
  column$name
}

data_dict_constraints <- function(column, path) {
  constraints <- column$constraints
  if (is.null(constraints)) {
    return(character())
  }
  if (is.character(constraints) && is.null(names(constraints))) {
    values <- as.list(constraints)
  } else if (data_dict_is_array(constraints)) {
    values <- constraints
  } else {
    data_dict_abort(
      "Column constraints must be one string or a flat array of strings.",
      field = paste0(path, ".constraints"),
      rule = "column_constraints"
    )
  }
  if (!all(vapply(values, data_dict_is_string, logical(1)))) {
    data_dict_abort(
      "Column constraints must be non-empty scalar strings.",
      field = paste0(path, ".constraints"),
      rule = "column_constraints"
    )
  }
  vapply(values, identity, character(1), USE.NAMES = FALSE)
}

data_dict_is_array <- function(value) {
  is.list(value) && !is.object(value) && is.null(names(value))
}

data_dict_is_string <- function(value) {
  is.character(value) &&
    length(value) == 1L &&
    !is.na(value) &&
    nzchar(trimws(value))
}

data_dict_abort <- function(message, field, rule, ...) {
  abort_schema_error(message, field = field, rule = rule, ...)
}
