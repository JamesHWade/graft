graft_definition_class_name <- "GraftDefinition"
graft_definition_view_name <- "graft_definition"

graft_definition_slot <- function(
  name,
  range = "string",
  duckdb_type = "VARCHAR",
  required = FALSE,
  identifier = FALSE
) {
  list(
    duckdb_type = duckdb_type,
    enum = NULL,
    external_identifier = NULL,
    identifier = identifier,
    maximum_value = NULL,
    meaning = NULL,
    minimum_value = NULL,
    multivalued = FALSE,
    name = name,
    object_reference = FALSE,
    ordered = FALSE,
    pattern = NULL,
    range = range,
    required = required,
    search_weight = NULL,
    sensitive = FALSE,
    view_column = name
  )
}

graft_definition_class_contract <- function() {
  list(
    ancestors = list(
      graft_definition_class_name,
      "GraftMetadata",
      "GraftRecord"
    ),
    fixed_predicate = NULL,
    id_format = "linkml",
    id_policy = "deterministic",
    is_a = "GraftMetadata",
    label_slot = "name",
    name = graft_definition_class_name,
    origin_key_slots = list("target", "name"),
    qualifier_slots = list(),
    relations = list(),
    role = "metadata",
    search_slots = list("label", "description", "details"),
    slots = list(
      id = graft_definition_slot(
        "id",
        range = "uriorcurie",
        required = TRUE,
        identifier = TRUE
      ),
      created_at = graft_definition_slot(
        "created_at",
        range = "datetime",
        duckdb_type = "TIMESTAMP"
      ),
      updated_at = graft_definition_slot(
        "updated_at",
        range = "datetime",
        duckdb_type = "TIMESTAMP"
      ),
      name = graft_definition_slot("name", required = TRUE),
      target = graft_definition_slot("target", required = TRUE),
      expr = graft_definition_slot("expr", required = TRUE),
      label = graft_definition_slot("label"),
      description = graft_definition_slot("description"),
      details = graft_definition_slot("details")
    ),
    statement_shape = NULL,
    type_uri = "https://w3id.org/graft/GraftDefinition",
    view = graft_definition_view_name
  )
}

augment_manifest_with_definitions <- function(compiled) {
  manifest <- compiled$manifest
  if (!is.null(manifest$classes[[graft_definition_class_name]])) {
    return(compiled)
  }
  taken_views <- vapply(
    manifest$classes,
    \(class) scalar_character(class$view),
    character(1)
  )
  if (graft_definition_view_name %in% taken_views) {
    abort_schema_error(
      paste0(
        "The view name `",
        graft_definition_view_name,
        "` is reserved for the graft definition system class."
      ),
      field = "view",
      rule = "reserved_definition_view"
    )
  }
  manifest$classes[[graft_definition_class_name]] <-
    graft_definition_class_contract()
  manifest$fingerprints$structural_digest <- manifest_structural_digest(
    manifest
  )
  manifest$fingerprints$build_digest <- manifest_build_digest(manifest)
  compiled$manifest <- manifest
  compiled
}

definition_public_scalar_columns <- function(contract) {
  slots <- Filter(
    \(slot) {
      !scalar_logical(slot$multivalued) &&
        !scalar_logical(slot$sensitive)
    },
    contract$slots
  )
  names(slots)
}

definition_expr_analyze <- function(
  expr,
  columns,
  definition_names = character()
) {
  checked <- definition_expr_check(
    expr,
    c(columns, definition_names),
    selection_columns = columns
  )
  if (nrow(checked$issues) > 0L) {
    return(list(
      issues = checked$issues,
      sql = NA_character_,
      kind = NA_character_,
      dependencies = character(),
      has_aggregate = FALSE,
      has_row_reference = FALSE,
      has_selection = FALSE
    ))
  }
  tokens <- definition_expr_tokenize(expr)
  texts <- vapply(tokens, `[[`, character(1), "text")
  types <- vapply(tokens, `[[`, character(1), "type")
  names <- texts
  quoted <- types == "quoted_identifier"
  names[quoted] <- vapply(
    texts[quoted],
    function(text) {
      gsub("``", "`", substr(text, 2L, nchar(text) - 1L), fixed = TRUE)
    },
    character(1)
  )
  upper <- toupper(texts)
  following <- c(texts[-1L], "")
  calls <- upper[
    types == "identifier" &
      following == "("
  ]
  identifier_positions <- types %in%
    c("identifier", "quoted_identifier") &
    (types == "quoted_identifier" | following != "(")
  identifiers <- names[identifier_positions]
  identifier_types <- types[identifier_positions]
  reserved <- c(
    "AND",
    "OR",
    "NOT",
    "TRUE",
    "FALSE",
    "DISTINCT"
  )
  dependencies <- unique(identifiers[
    (identifier_types == "quoted_identifier" |
      !toupper(identifiers) %in% reserved) &
      identifiers %in% definition_names &
      !identifiers %in% columns
  ])
  has_aggregate <- any(calls %in% definition_expr_aggregates)
  has_row_reference <- any(identifiers %in% columns) ||
    any(calls %in% "COLUMNS")
  has_predicate <- any(
    types == "operator" &
      texts %in% c("=", "!=", "<", "<=", ">", ">=")
  ) ||
    any(
      calls %in%
        c(
          "STARTS_WITH",
          "ENDS_WITH",
          "IS_FINITE",
          "IS_INFINITE",
          "IS_NAN"
        )
    ) ||
    any(
      upper %in%
        c(
          "AND",
          "OR",
          "NOT",
          "TRUE",
          "FALSE",
          "IS",
          "BETWEEN",
          "IN",
          "LIKE",
          "SIMILAR"
        )
    )
  kind <- if (has_aggregate) {
    "metric"
  } else if (!has_row_reference && length(dependencies) == 0L) {
    "metric"
  } else if (has_predicate) {
    "filter"
  } else {
    "derived"
  }
  list(
    issues = definition_expr_no_issues(),
    sql = checked$sql,
    kind = kind,
    dependencies = dependencies,
    has_aggregate = has_aggregate,
    has_row_reference = has_row_reference,
    has_selection = !is.null(checked$selection)
  )
}

validate_definition_candidates <- function(
  manifest,
  staged,
  current,
  connection
) {
  issues <- list()
  data <- staged$data
  accepted <- definition_current_records(current)
  candidates <- data.frame(
    id = as.character(data$id),
    name = as.character(data$name),
    target = as.character(data$target),
    expr = as.character(data$expr),
    input_row = seq_len(nrow(data)),
    candidate = TRUE,
    stringsAsFactors = FALSE
  )
  previous_targets <- accepted$target[match(candidates$id, accepted$id)]
  accepted <- accepted[!accepted$id %in% candidates$id, , drop = FALSE]
  definitions <- dplyr::bind_rows(accepted, candidates)
  add_issue <- function(index, field, rule, message) {
    issues[[length(issues) + 1L]] <<- new_plan_issue(
      record_class = staged$class,
      input_row = index,
      record_id = scalar_character(data$id[[index]]),
      field = field,
      rule = rule,
      message = message
    )
  }
  for (index in seq_len(nrow(data))) {
    target <- scalar_character(data$target[[index]])
    contract <- definition_target_contract_or_null(manifest, target)
    if (
      is.na(target) ||
        is.null(contract)
    ) {
      if (!is.na(target)) {
        add_issue(
          index,
          "target",
          "definition_target",
          paste0("`", target, "` is not a public definition target.")
        )
      }
      next
    }
    columns <- definition_public_scalar_columns(contract)
    name <- scalar_character(data$name[[index]])
    if (!is.na(name) && name %in% columns) {
      add_issue(
        index,
        "name",
        "definition_column_shadow",
        paste0("Definition `", name, "` shadows a column of `", target, "`.")
      )
    }
    local_names <- as.character(definitions$name[
      definitions$target == target &
        !is.na(definitions$name) &
        nzchar(definitions$name)
    ])
    expr <- scalar_character(data$expr[[index]])
    if (!is.na(expr)) {
      checked <- definition_expr_analyze(expr, columns, local_names)
      for (row in seq_len(nrow(checked$issues))) {
        add_issue(
          index,
          "expr",
          checked$issues$rule[[row]],
          checked$issues$message[[row]]
        )
      }
    }
  }
  complete <- !is.na(definitions$target) &
    nzchar(definitions$target) &
    !is.na(definitions$name) &
    nzchar(definitions$name) &
    !is.na(definitions$expr) &
    nzchar(definitions$expr)
  keys <- paste(definitions$target, definitions$name, sep = "\r")
  complete_keys <- keys[complete]
  duplicate_keys <- unique(complete_keys[duplicated(complete_keys)])
  for (index in seq_len(nrow(data))) {
    if (
      paste(data$target[[index]], data$name[[index]], sep = "\r") %in%
        duplicate_keys
    ) {
      add_issue(
        index,
        "name",
        "definition_name_unique",
        "Definition names must be unique within a public table."
      )
    }
  }
  for (target in unique(as.character(definitions$target[complete]))) {
    contract <- definition_target_contract_or_null(manifest, target)
    if (is.null(contract)) {
      next
    }
    target_candidate_indices <- candidates$input_row[
      (!is.na(candidates$target) & candidates$target == target) |
        (!is.na(previous_targets) & previous_targets == target)
    ]
    if (length(target_candidate_indices) == 0L) {
      next
    }
    target_rows <- definitions[
      complete &
        definitions$target == target &
        !keys %in% duplicate_keys,
      ,
      drop = FALSE
    ]
    definition_names <- as.character(target_rows$name)
    graph <- stats::setNames(
      vector("list", nrow(target_rows)),
      definition_names
    )
    columns <- definition_public_scalar_columns(contract)
    for (position in seq_len(nrow(target_rows))) {
      analysis <- definition_expr_analyze(
        scalar_character(target_rows$expr[[position]]),
        columns,
        definition_names
      )
      graph[[position]] <- analysis$dependencies
    }
    cycle_names <- definition_cycle_members(graph)
    for (name in cycle_names) {
      indices <- which(data$target == target & data$name == name)
      for (index in indices) {
        add_issue(
          index,
          "expr",
          "definition_cycle",
          paste0(
            "Definition `",
            name,
            "` participates in a dependency cycle."
          )
        )
      }
    }
    direct_selections <- stats::setNames(
      vapply(
        seq_len(nrow(target_rows)),
        function(position) {
          analysis <- definition_expr_analyze(
            scalar_character(target_rows$expr[[position]]),
            columns,
            definition_names
          )
          as.integer(analysis$has_selection)
        },
        integer(1)
      ),
      definition_names
    )
    selection_counts <- stats::setNames(
      rep(NA_integer_, length(definition_names)),
      definition_names
    )
    selection_count <- function(name, active = character()) {
      if (name %in% active) {
        return(NA_integer_)
      }
      if (!is.na(selection_counts[[name]])) {
        return(selection_counts[[name]])
      }
      dependencies <- vapply(
        graph[[name]],
        \(dependency) selection_count(dependency, c(active, name)),
        integer(1)
      )
      if (anyNA(dependencies)) {
        return(NA_integer_)
      }
      selection_counts[[name]] <<- direct_selections[[name]] +
        sum(dependencies)
      selection_counts[[name]]
    }
    for (name in definition_names) {
      selection_count(name)
    }
    invalid_selection_names <- names(selection_counts)[
      !is.na(selection_counts) & selection_counts > 1L
    ]
    for (name in invalid_selection_names) {
      indices <- which(data$target == target & data$name == name)
      for (index in indices) {
        add_issue(
          index,
          "expr",
          "definition_expr_selection",
          paste0(
            "Definition `",
            name,
            "` recursively uses more than one `COLUMNS()` selection."
          )
        )
      }
    }
    invalid_names <- c(cycle_names, invalid_selection_names)
    catalog <- target_rows
    compiler <- new.env(parent = emptyenv())
    compiler$catalog <- catalog
    compiler$columns <- columns
    compiler$target <- target
    compiler$compiled <- list()
    compiler$active <- character()
    source_sql <- definition_empty_source_sql(connection, contract)
    validation_rows <- which(!target_rows$name %in% invalid_names)
    for (position in validation_rows) {
      candidate_index <- if (target_rows$candidate[[position]]) {
        target_rows$input_row[[position]]
      } else {
        target_candidate_indices[[1L]]
      }
      basic <- definition_expr_analyze(
        target_rows$expr[[position]],
        columns,
        definition_names
      )
      if (nrow(basic$issues) > 0L) {
        if (!target_rows$candidate[[position]]) {
          add_issue(
            candidate_index,
            "expr",
            "definition_expr_type",
            paste0(
              "Definition `",
              target_rows$name[[position]],
              "` does not type-check for `",
              target,
              "`."
            )
          )
        }
        next
      }
      error <- tryCatch(
        {
          compiled <- definition_compile_row(
            target_rows[position, , drop = FALSE],
            compiler
          )
          type <- definition_describe_sql(
            connection,
            compiled$sql,
            source_sql
          )
          if (
            selection_counts[[target_rows$name[[position]]]] > 0L &&
              !grepl("^BOOLEAN", toupper(type))
          ) {
            rlang::abort("A `COLUMNS()` selection must produce a filter.")
          }
          NULL
        },
        error = identity
      )
      if (!is.null(error)) {
        add_issue(
          candidate_index,
          "expr",
          "definition_expr_type",
          paste0(
            "Definition `",
            target_rows$name[[position]],
            "` does not type-check for `",
            target,
            "`."
          )
        )
      }
    }
  }
  issues
}

definition_target_contract_or_null <- function(manifest, target) {
  if (is.na(target) || identical(target, graft_definition_class_name)) {
    return(NULL)
  }
  contract <- manifest$classes[[target]]
  if (!is.null(contract)) {
    return(contract)
  }
  matches <- Filter(
    \(relation) identical(scalar_character(relation$view), target),
    manifest$relations
  )
  if (length(matches) != 1L) {
    return(NULL)
  }
  relation <- matches[[1L]]
  owner <- scalar_character(relation$owner_class)
  slot <- manifest$classes[[owner]]$slots[[scalar_character(relation$slot)]]
  if (scalar_logical(slot$sensitive)) {
    return(NULL)
  }
  definition_relation_contract(relation, slot)
}

definition_relation_contract <- function(relation, value_slot) {
  relation_slot <- function(
    name,
    duckdb_type,
    range = "string",
    identifier = FALSE
  ) {
    graft_definition_slot(
      name,
      range = range,
      duckdb_type = duckdb_type,
      required = FALSE,
      identifier = identifier
    )
  }
  slots <- if (identical(scalar_character(relation$kind), "object")) {
    list(
      id = relation_slot("id", "VARCHAR", "uriorcurie", identifier = TRUE),
      subject = relation_slot("subject", "VARCHAR", "uriorcurie"),
      object = relation_slot("object", "VARCHAR", "uriorcurie"),
      position = relation_slot("position", "BIGINT", "integer"),
      created_at = relation_slot("created_at", "TIMESTAMP", "datetime")
    )
  } else {
    value <- relation_slot(
      "value",
      scalar_character(value_slot$duckdb_type),
      scalar_character(value_slot$range)
    )
    value$enum <- value_slot$enum
    list(
      owner_id = relation_slot("owner_id", "VARCHAR", "uriorcurie"),
      position = relation_slot("position", "BIGINT", "integer"),
      value = value
    )
  }
  list(
    name = scalar_character(relation$view),
    slots = slots,
    relation = relation
  )
}

definition_empty_source_sql <- function(connection, contract) {
  columns <- definition_public_scalar_columns(contract)
  selections <- vapply(
    columns,
    function(column) {
      paste0(
        "CAST(NULL AS ",
        safe_duckdb_type(scalar_character(
          contract$slots[[column]]$duckdb_type
        )),
        ") AS ",
        quote_identifier(connection, column)
      )
    },
    character(1)
  )
  paste0(
    "SELECT ",
    paste(selections, collapse = ", "),
    " WHERE FALSE"
  )
}

definition_describe_sql <- function(connection, sql, source_sql) {
  description <- DBI::dbGetQuery(
    connection,
    paste0(
      "DESCRIBE SELECT ",
      sql,
      " AS definition_value FROM (",
      source_sql,
      ") definition_target"
    )
  )
  scalar_character(description$column_type[[1L]])
}

definition_current_records <- function(current) {
  rows <- current[
    current$class == graft_definition_class_name &
      current$operation != "delete",
    ,
    drop = FALSE
  ]
  if (nrow(rows) == 0L) {
    return(data.frame(
      id = character(),
      name = character(),
      target = character(),
      expr = character(),
      input_row = integer(),
      candidate = logical(),
      stringsAsFactors = FALSE
    ))
  }
  payloads <- lapply(
    rows$payload_json,
    jsonlite::fromJSON,
    simplifyVector = FALSE
  )
  data.frame(
    id = as.character(rows$record_id),
    name = vapply(
      payloads,
      \(payload) scalar_character(payload$name),
      character(1)
    ),
    target = vapply(
      payloads,
      \(payload) scalar_character(payload$target),
      character(1)
    ),
    expr = vapply(
      payloads,
      \(payload) scalar_character(payload$expr),
      character(1)
    ),
    input_row = NA_integer_,
    candidate = FALSE,
    stringsAsFactors = FALSE
  )
}

definition_cycle_members <- function(graph) {
  if (length(graph) == 0L) {
    return(character())
  }
  state <- stats::setNames(integer(length(graph)), names(graph))
  stack <- character()
  cycles <- character()
  visit <- function(name) {
    if (state[[name]] == 2L) {
      return(invisible(NULL))
    }
    if (state[[name]] == 1L) {
      start <- match(name, stack)
      cycles <<- unique(c(cycles, stack[seq.int(start, length(stack))]))
      return(invisible(NULL))
    }
    state[[name]] <<- 1L
    stack <<- c(stack, name)
    for (dependency in graph[[name]]) {
      if (dependency %in% names(graph)) {
        visit(dependency)
      }
    }
    stack <<- utils::head(stack, -1L)
    state[[name]] <<- 2L
    invisible(NULL)
  }
  for (name in names(graph)) {
    visit(name)
  }
  sort(unique(cycles), method = "radix")
}

contract_definition_records <- function(manifest) {
  document <- manifest$dictionary$document
  if (is.null(document)) {
    return(NULL)
  }
  rows <- list()
  for (table in document$tables) {
    definitions <- table$definitions
    if (is.null(definitions)) {
      next
    }
    for (definition in definitions) {
      rows[[length(rows) + 1L]] <- data.frame(
        name = scalar_character(definition$name),
        target = scalar_character(table$name),
        expr = scalar_character(definition$expr),
        label = scalar_character(definition$label),
        description = scalar_character(definition$description),
        details = scalar_character(definition$details),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0L) {
    return(NULL)
  }
  do.call(rbind, rows)
}

seed_contract_definitions <- function(store, compiled_schema) {
  store <- as_graft_store_internal(store, "store")
  records <- contract_definition_records(compiled_schema$manifest)
  if (is.null(records)) {
    with_duckdb_error(
      "seed_contract_definitions",
      DBI::dbWithTransaction(
        store$connection,
        mark_contract_definitions_seeded(store$connection)
      )
    )
    return(invisible(store))
  }
  plan <- graft_plan_records(
    store = store,
    records = stats::setNames(list(records), graft_definition_class_name),
    provenance = graft_provenance(
      producer = "contract",
      idempotency_key = paste0(
        "contract-definitions:",
        compiled_schema$manifest$fingerprints$source_digest
      )
    ),
    source = "records"
  )
  commit_graft_plan(
    store,
    plan,
    finalize = mark_contract_definitions_seeded
  )
  invisible(store)
}
