snapshot_identifier_registry <- function(store) {
  snapshot <- snapshot_backend_data(store)
  rows <- retrieval_query(
    store$connection,
    paste0(
      "SELECT o.record_id, o.class, o.batch_id, o.revision_id, ",
      "o.observed_at, b.commit_order, ",
      "b.schema_build_digest AS observation_schema_build_digest, ",
      "r.schema_build_digest AS revision_schema_build_digest, ",
      "r.payload_json, r.content_digest FROM ",
      quote_identifier(store$connection, "_graft_record_observations"),
      " o INNER JOIN ",
      quote_identifier(store$connection, "_graft_batches"),
      " b ON o.batch_id = b.batch_id INNER JOIN ",
      quote_identifier(store$connection, "_graft_record_revisions"),
      " r ON o.revision_id = r.revision_id AND o.record_id = r.record_id ",
      "AND o.class = r.class WHERE b.status = 'committed' ",
      "AND b.commit_order <= ? ORDER BY b.commit_order, o.class, ",
      "o.record_id, o.batch_id, o.revision_id"
    ),
    params = list(snapshot$commit_order)
  )
  if (nrow(rows) == 0L) {
    return(empty_snapshot_identifier_registry())
  }
  digests <- unique(c(
    rows$observation_schema_build_digest,
    rows$revision_schema_build_digest
  ))
  schemas <- historical_schemas(store, digests)
  events <- list()
  for (index in seq_len(nrow(rows))) {
    record_class <- rows$class[[index]]
    revision_schema <- schemas[[rows$revision_schema_build_digest[[index]]]]
    revision_contract <- revision_schema$manifest$classes[[record_class]]
    observation_schema <- schemas[[
      rows$observation_schema_build_digest[[index]]
    ]]
    observation_contract <- observation_schema$manifest$classes[[record_class]]
    if (is.null(revision_contract) || is.null(observation_contract)) {
      abort_snapshot_error(
        "graft_snapshot_schema_error",
        "An observed identifier class is absent from its historical contract.",
        record_id = rows$record_id[[index]],
        record_class = record_class,
        revision_id = rows$revision_id[[index]]
      )
    }
    validated_public_revision_record(
      rows$payload_json[[index]],
      rows$content_digest[[index]],
      revision_contract,
      record_id = rows$record_id[[index]],
      revision_id = rows$revision_id[[index]]
    )
    payload <- parse_revision_payload(rows$payload_json[[index]])
    identifiers <- external_identifiers_for_row(
      observation_contract,
      payload
    )$identifiers
    if (length(identifiers) == 0L) {
      next
    }
    for (identifier in identifiers) {
      if (
        is.na(identifier$normalized_value) ||
          !nzchar(identifier$normalized_value)
      ) {
        next
      }
      events[[length(events) + 1L]] <- data.frame(
        record_id = rows$record_id[[index]],
        class = record_class,
        namespace = identifier$namespace,
        value = identifier$value,
        normalized_value = identifier$normalized_value,
        slot = identifier$slot,
        commit_order = as.numeric(rows$commit_order[[index]]),
        batch_id = rows$batch_id[[index]],
        created_at = as.POSIXct(rows$observed_at[[index]], tz = "UTC"),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(events) == 0L) {
    return(empty_snapshot_identifier_registry())
  }
  events <- dplyr::bind_rows(events)
  events <- events[
    order(
      events$commit_order,
      events$class,
      events$record_id,
      events$namespace,
      events$normalized_value,
      events$slot,
      events$batch_id,
      method = "radix"
    ),
    ,
    drop = FALSE
  ]
  identifier_key <- paste(
    events$class,
    events$namespace,
    events$normalized_value,
    sep = "\u001f"
  )
  owners <- split(events$record_id, identifier_key)
  conflicts <- names(Filter(\(ids) length(unique(ids)) > 1L, owners))
  if (length(conflicts) > 0L) {
    conflict <- conflicts[[1L]]
    parts <- strsplit(conflict, "\u001f", fixed = TRUE)[[1L]]
    abort_identity_error(
      "A snapshot identifier maps to multiple records.",
      record_class = parts[[1L]],
      namespace = parts[[2L]],
      normalized_value = parts[[3L]],
      matched_record_ids = unique(owners[[conflict]]),
      rule = "unique_active_identifier"
    )
  }
  record_key <- paste(events$class, events$record_id, sep = "\u001f")
  primary_index <- !duplicated(record_key)
  primary <- stats::setNames(
    identifier_key[primary_index],
    record_key[primary_index]
  )
  events$status <- ifelse(
    identifier_key == unname(primary[record_key]),
    "primary",
    "equivalent"
  )
  latest <- !duplicated(identifier_key, fromLast = TRUE)
  events <- events[latest, , drop = FALSE]
  result <- data.frame(
    record_id = events$record_id,
    class = events$class,
    namespace = events$namespace,
    value = events$value,
    normalized_value = events$normalized_value,
    status = events$status,
    assigned_by = rep("authoritative", nrow(events)),
    confidence = rep(1, nrow(events)),
    created_at = events$created_at,
    stringsAsFactors = FALSE
  )
  rownames(result) <- NULL
  result
}

snapshot_public_identifier_rows <- function(store, id, limit) {
  rows <- snapshot_identifier_registry(store)
  eligible <- character()
  for (record_class in public_class_names(store)) {
    contract <- store$schema$manifest$classes[[record_class]]
    namespaces <- vapply(
      Filter(
        \(slot) {
          !scalar_logical(slot$sensitive) &&
            !is.na(scalar_character(slot$external_identifier))
        },
        contract$slots
      ),
      \(slot) scalar_character(slot$external_identifier),
      character(1)
    )
    eligible <- c(
      eligible,
      paste(record_class, namespaces, sep = "\u001f")
    )
  }
  pair <- paste(rows$class, rows$namespace, sep = "\u001f")
  rows <- rows[rows$record_id == id & pair %in% eligible, , drop = FALSE]
  status_order <- match(
    rows$status,
    c("primary", "equivalent", "candidate"),
    nomatch = 4L
  )
  rows <- rows[
    order(
      rows$class,
      status_order,
      rows$namespace,
      rows$normalized_value,
      method = "radix"
    ),
    ,
    drop = FALSE
  ]
  trim_bounded_rows(rows, store, limit)
}

empty_snapshot_identifier_registry <- function() {
  data.frame(
    record_id = character(),
    class = character(),
    namespace = character(),
    value = character(),
    normalized_value = character(),
    status = character(),
    assigned_by = character(),
    confidence = numeric(),
    created_at = as.POSIXct(character(), tz = "UTC"),
    stringsAsFactors = FALSE
  )
}

snapshot_graph_data <- function(store) {
  current <- retrieval_query(
    store$connection,
    paste0(
      "SELECT * FROM (",
      graft_read_source_sql(store),
      ") current ORDER BY class, record_id, revision_id"
    )
  )
  records <- lapply(seq_len(nrow(current)), function(index) {
    graft_public_current_record(store, current[index, , drop = FALSE])
  })
  current$record <- I(records)
  list(
    nodes = snapshot_graph_nodes(current, store$schema, store$connection),
    semantic = snapshot_graph_semantic_edges(current, store$schema),
    provenance = snapshot_graph_provenance_edges(current, store$schema)
  )
}

snapshot_graph_nodes <- function(current, schema, connection) {
  classes <- graph_projection_classes(schema, "node_classes")
  nodes <- list()
  for (index in seq_len(nrow(current))) {
    record_class <- current$class[[index]]
    if (!record_class %in% classes) {
      next
    }
    contract <- graph_projection_contract(schema, record_class, "nodes")
    record <- current$record[[index]]
    payload <- parse_revision_payload(current$payload_json[[index]])
    nodes[[length(nodes) + 1L]] <- data.frame(
      id = snapshot_graph_scalar(record, "id"),
      class = record_class,
      label = snapshot_graph_label(connection, payload, contract),
      role = scalar_character(contract$role),
      statement_shape = scalar_character(contract$statement_shape),
      type_uri = scalar_character(contract$type_uri),
      created_at = snapshot_graph_time(record, "created_at"),
      stringsAsFactors = FALSE
    )
  }
  if (length(nodes) == 0L) {
    return(graph_empty_node_data())
  }
  result <- dplyr::bind_rows(nodes)
  result <- result[order(result$id, result$class), , drop = FALSE]
  rownames(result) <- NULL
  result
}

snapshot_graph_label <- function(connection, payload, contract) {
  for (field in graph_label_slots(contract)) {
    value <- payload[[field]]
    if (is.null(value) || length(value) == 0L || is.na(value[[1L]])) {
      next
    }
    type <- safe_duckdb_type(contract$slots[[field]]$duckdb_type)
    value <- retrieval_query(
      connection,
      paste0(
        "SELECT NULLIF(TRIM(CAST(CAST(? AS ",
        type,
        ") AS VARCHAR)), '') AS label"
      ),
      params = list(value[[1L]])
    )$label[[1L]]
    if (!is.na(value)) {
      return(value)
    }
  }
  NA_character_
}

snapshot_graph_semantic_edges <- function(current, schema) {
  manifest <- schema$manifest
  projection <- manifest$graph_projections$semantic_edges
  direct <- empty_character(projection$direct_edge_classes)
  if (length(direct) == 0L) {
    direct <- names(Filter(
      \(contract) identical(scalar_character(contract$role), "edge"),
      manifest$classes
    ))
  }
  semantic <- empty_character(projection$semantic_statement_classes)
  if (length(semantic) == 0L) {
    semantic <- names(Filter(
      \(contract) {
        identical(scalar_character(contract$statement_shape), "semantic")
      },
      manifest$classes
    ))
  }
  edges <- list()
  for (index in seq_len(nrow(current))) {
    record_class <- current$class[[index]]
    record <- current$record[[index]]
    contract <- manifest$classes[[record_class]]
    if (record_class %in% direct) {
      fixed <- scalar_character(contract$fixed_predicate)
      predicate <- if (is.na(fixed)) {
        snapshot_graph_scalar(record, "predicate")
      } else {
        fixed
      }
      edges[[length(edges) + 1L]] <- snapshot_graph_edge_row(
        edge_id = snapshot_graph_scalar(record, "id"),
        subject = snapshot_graph_scalar(record, "subject"),
        predicate = predicate,
        object = snapshot_graph_scalar(record, "object"),
        edge_class = record_class,
        source_table = scalar_character(contract$view),
        created_at = snapshot_graph_time(record, "created_at")
      )
    }
    if (record_class %in% semantic) {
      object <- snapshot_graph_scalar(record, "object_entity")
      if (!is.na(object)) {
        edges[[length(edges) + 1L]] <- snapshot_graph_edge_row(
          edge_id = snapshot_graph_scalar(record, "id"),
          subject = snapshot_graph_scalar(record, "subject"),
          predicate = snapshot_graph_scalar(record, "predicate"),
          object = object,
          edge_class = record_class,
          source_table = scalar_character(contract$view),
          created_at = snapshot_graph_time(record, "created_at")
        )
      }
    }
  }
  snapshot_graph_bind_edges(edges)
}

snapshot_graph_provenance_edges <- function(current, schema) {
  manifest <- schema$manifest
  projection <- manifest$graph_projections$provenance_edges
  narrative <- empty_character(projection$narrative_statement_classes)
  if (length(narrative) == 0L) {
    narrative <- names(Filter(
      \(contract) {
        identical(scalar_character(contract$statement_shape), "narrative")
      },
      manifest$classes
    ))
  }
  narrative_slots <- empty_character(projection$narrative_slots)
  if (length(narrative_slots) == 0L) {
    narrative_slots <- c("about", "primary_subject")
  }
  edges <- list()
  add_scalar <- function(
    index,
    subject_slot,
    object_slot,
    predicate,
    kind,
    owner_slot = subject_slot
  ) {
    record <- current$record[[index]]
    contract <- manifest$classes[[current$class[[index]]]]
    required <- c(subject_slot, object_slot, owner_slot)
    if (!all(required %in% names(contract$slots))) {
      return(invisible(NULL))
    }
    subject <- snapshot_graph_scalar(record, subject_slot)
    object <- snapshot_graph_scalar(record, object_slot)
    owner <- snapshot_graph_scalar(record, owner_slot)
    if (is.na(subject) || is.na(object) || is.na(owner)) {
      return(invisible(NULL))
    }
    edges[[length(edges) + 1L]] <<- snapshot_graph_edge_row(
      edge_id = paste0(owner, "#", kind),
      subject = subject,
      predicate = predicate,
      object = object,
      edge_class = "provenance",
      source_table = scalar_character(contract$view),
      created_at = as.POSIXct(NA, tz = "UTC")
    )
    invisible(NULL)
  }
  if ("about" %in% narrative_slots) {
    relations <- Filter(
      \(relation) {
        scalar_character(relation$owner_class) %in%
          narrative &&
          identical(scalar_character(relation$slot), "about") &&
          identical(scalar_character(relation$kind), "object")
      },
      manifest$relations
    )
    for (relation in relations) {
      record_class <- scalar_character(relation$owner_class)
      indexes <- which(current$class == record_class)
      for (index in indexes) {
        owner <- current$record_id[[index]]
        values <- snapshot_graph_values(current$record[[index]], "about")
        for (position in seq_along(values)) {
          edges[[length(edges) + 1L]] <- snapshot_graph_edge_row(
            edge_id = paste0(owner, "#about:", position, "#about"),
            subject = owner,
            predicate = scalar_character(relation$predicate),
            object = values[[position]],
            edge_class = "provenance",
            source_table = scalar_character(relation$view),
            created_at = as.POSIXct(NA, tz = "UTC")
          )
        }
      }
    }
  }
  if ("primary_subject" %in% narrative_slots) {
    for (index in which(current$class %in% narrative)) {
      contract <- manifest$classes[[current$class[[index]]]]
      add_scalar(
        index,
        "id",
        "primary_subject",
        graph_slot_predicate(contract, "primary_subject"),
        "primary_subject"
      )
    }
  }
  if (scalar_logical(projection$statement_to_evidence, TRUE)) {
    for (index in which(
      current$class %in%
        graph_role_class_names(
          schema,
          "evidence"
        )
    )) {
      add_scalar(
        index,
        "statement_id",
        "id",
        graft_predicate_uri("evidence"),
        "statement_evidence",
        owner_slot = "id"
      )
    }
  }
  if (scalar_logical(projection$evidence_to_source, TRUE)) {
    for (index in which(
      current$class %in%
        graph_role_class_names(
          schema,
          "evidence"
        )
    )) {
      contract <- manifest$classes[[current$class[[index]]]]
      add_scalar(
        index,
        "id",
        "source_id",
        graph_slot_predicate(contract, "source_id"),
        "evidence_source"
      )
    }
  }
  if (scalar_logical(projection$supersession, TRUE)) {
    for (index in which(
      current$class %in%
        graph_role_class_names(
          schema,
          "statement"
        )
    )) {
      contract <- manifest$classes[[current$class[[index]]]]
      add_scalar(
        index,
        "id",
        "superseded_by",
        graph_slot_predicate(contract, "superseded_by"),
        "superseded_by"
      )
    }
  }
  if (scalar_logical(projection$mention_resolution, TRUE)) {
    for (index in which(
      current$class %in%
        graph_role_class_names(
          schema,
          "mention"
        )
    )) {
      contract <- manifest$classes[[current$class[[index]]]]
      add_scalar(
        index,
        "id",
        "entity_id",
        graph_slot_predicate(contract, "entity_id"),
        "mention_entity"
      )
    }
  }
  if (scalar_logical(projection$semantic_derivation, TRUE)) {
    semantic <- names(Filter(
      \(contract) {
        identical(scalar_character(contract$statement_shape), "semantic")
      },
      manifest$classes
    ))
    for (index in which(current$class %in% semantic)) {
      contract <- manifest$classes[[current$class[[index]]]]
      add_scalar(
        index,
        "id",
        "derived_from_statement",
        graph_slot_predicate(contract, "derived_from_statement"),
        "semantic_derivation"
      )
    }
  }
  snapshot_graph_bind_edges(edges)
}

snapshot_graph_scalar <- function(record, field) {
  value <- retrieval_record_scalar(record, field)
  if (length(value) == 0L || is.null(value) || is.na(value[[1L]])) {
    return(NA_character_)
  }
  as.character(value[[1L]])
}

snapshot_graph_values <- function(record, field) {
  value <- record[[field]]
  if (is.null(value) || length(value) == 0L) {
    return(character())
  }
  value <- as.character(unlist(value, use.names = FALSE))
  value[!is.na(value)]
}

snapshot_graph_time <- function(record, field) {
  value <- retrieval_record_scalar(record, field, NA)
  if (length(value) == 0L || is.null(value) || is.na(value[[1L]])) {
    return(as.POSIXct(NA, tz = "UTC"))
  }
  as.POSIXct(value[[1L]], tz = "UTC")
}

snapshot_graph_edge_row <- function(
  edge_id,
  subject,
  predicate,
  object,
  edge_class,
  source_table,
  created_at
) {
  data.frame(
    edge_id = edge_id,
    subject = subject,
    predicate = predicate,
    object = object,
    edge_class = edge_class,
    source_table = source_table,
    created_at = created_at,
    stringsAsFactors = FALSE
  )
}

snapshot_graph_bind_edges <- function(edges) {
  if (length(edges) == 0L) {
    return(graph_empty_edge_data())
  }
  graph_order_edges(dplyr::bind_rows(edges))
}
