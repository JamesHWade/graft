test_that("migration plans are deterministic and compatible activations apply", {
  schema <- kg_schema(tempest_manifest_path())
  store <- local_ingest_store(schema = schema)
  rebuilt <- migration_schema_copy(schema, "rebuilt", structural = FALSE)

  first <- kg_plan_migration(store, rebuilt)
  second <- kg_plan_migration(store, rebuilt)
  restored <- unserialize(serialize(first, NULL))

  expect_s3_class(first, "kg_migration_plan")
  expect_identical(first, second)
  expect_identical(restored, first)
  expect_identical(first$classification, "compatible")
  expect_equal(nrow(first$changes), 0L)
  expect_length(first$operations, 0L)
  expect_match(first$plan_digest, "^sha256:")

  expect_invisible(kg_apply_migration(store, first))

  metadata <- DBI::dbReadTable(store$connection, "_graft_store")
  migrations <- DBI::dbReadTable(store$connection, "_graft_migrations")
  activations <- DBI::dbReadTable(
    store$connection,
    "_graft_schema_activations"
  )
  expect_identical(metadata$active_build_digest, first$to_build_digest)
  expect_identical(store$schema$manifest, rebuilt$manifest)
  expect_identical(migrations$plan_digest, first$plan_digest)
  expect_identical(migrations$classification, "compatible")
  expect_identical(
    jsonlite::fromJSON(migrations$changes_json, simplifyVector = FALSE),
    list()
  )
  expect_identical(activations$reason, c("initial", "migration"))
})

test_that("nullable slots preserve old heads and create the first new revision", {
  schema <- kg_schema(tempest_manifest_path())
  store <- local_ingest_store(schema = schema)
  input <- data.frame(
    preferred_name = "Project Firefly",
    .graft_origin_key = "firefly",
    check.names = FALSE
  )
  first <- kg_write(
    store,
    kg_batch("portfolio", idempotency_key = "firefly-1"),
    "Entity",
    input
  )
  revision_before <- DBI::dbReadTable(
    store$connection,
    "_graft_record_revisions"
  )
  migrated <- migration_schema_add_slot(schema)
  plan <- kg_plan_migration(store, migrated)

  expect_identical(plan$classification, "additive")
  expect_identical(
    vapply(plan$operations, \(.x) .x$kind, character(1)),
    "add_column"
  )
  kg_apply_migration(store, plan)
  expect_in("decision_note", DBI::dbListFields(store$connection, "entity"))

  matched <- kg_write(
    store,
    kg_batch("portfolio", idempotency_key = "firefly-2"),
    "Entity",
    input
  )
  expect_identical(matched$matched[["Entity"]], 1L)
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_record_revisions")),
    1L
  )

  updated <- transform(input, decision_note = "Advance to concept review")
  result <- kg_write(
    store,
    kg_batch("portfolio", idempotency_key = "firefly-3"),
    "Entity",
    updated
  )
  revisions <- DBI::dbReadTable(
    store$connection,
    "_graft_record_revisions"
  )
  changed <- jsonlite::fromJSON(
    revisions$changed_fields_json[[2L]],
    simplifyVector = FALSE
  )

  expect_identical(first$inserted[["Entity"]], 1L)
  expect_identical(result$updated[["Entity"]], 1L)
  expect_equal(nrow(revisions), 2L)
  expect_identical(revision_before$schema_build_digest, plan$from_build_digest)
  expect_identical(revisions$schema_build_digest[[2L]], plan$to_build_digest)
  expect_identical(unlist(changed, use.names = FALSE), "decision_note")
})

test_that("old-field updates after migration remain valid historical revisions", {
  schema <- kg_schema(tempest_manifest_path())
  store <- local_ingest_store(schema = schema)
  input <- data.frame(
    preferred_name = "Project Firefly",
    .graft_origin_key = "old-field",
    check.names = FALSE
  )
  kg_write(
    store,
    kg_batch("portfolio", idempotency_key = "old-field-1"),
    "Entity",
    input
  )
  migrated <- migration_schema_add_slot(schema, "optional_context")
  kg_apply_migration(store, kg_plan_migration(store, migrated))

  result <- kg_write(
    store,
    kg_batch("portfolio", idempotency_key = "old-field-2"),
    "Entity",
    transform(input, preferred_name = "Project Firefly II")
  )
  revisions <- DBI::dbReadTable(
    store$connection,
    "_graft_record_revisions"
  )
  changed <- jsonlite::fromJSON(
    revisions$changed_fields_json[[2L]],
    simplifyVector = FALSE
  )
  check <- kg_check_store(store, deep = TRUE)

  expect_identical(result$updated[["Entity"]], 1L)
  expect_identical(unlist(changed, use.names = FALSE), "preferred_name")
  expect_identical(check$valid, TRUE)
  expect_equal(check$reported_issues, 0L)
})

test_that("new concrete classes rebuild graph views", {
  schema <- kg_schema(tempest_manifest_path())
  store <- local_ingest_store(schema = schema)
  migrated <- migration_schema_add_class(schema)
  plan <- kg_plan_migration(store, migrated)

  expect_in(
    "create_table",
    vapply(
      plan$operations,
      \(.x) .x$kind,
      character(1)
    )
  )
  kg_apply_migration(store, plan)
  result <- kg_write(
    store,
    kg_batch("portfolio", idempotency_key = "portfolio-item"),
    "PortfolioItem",
    data.frame(
      preferred_name = "Project Firefly",
      .graft_origin_key = "portfolio-item",
      check.names = FALSE
    )
  )
  nodes <- DBI::dbReadTable(store$connection, "_graft_nodes")

  expect_identical(result$inserted[["PortfolioItem"]], 1L)
  expect_in("portfolio_item", DBI::dbListTables(store$connection))
  expect_in("PortfolioItem", nodes$class)
  expect_in("_graft_edges", DBI::dbListTables(store$connection))
})

test_that("generated relation tables are created and writable", {
  schema <- kg_schema(tempest_manifest_path())
  store <- local_ingest_store(schema = schema)
  migrated <- migration_schema_add_relation(schema)
  plan <- kg_plan_migration(store, migrated)

  expect_in(
    "create_relation",
    vapply(
      plan$operations,
      \(.x) .x$kind,
      character(1)
    )
  )
  kg_apply_migration(store, plan)
  result <- kg_write(
    store,
    kg_batch("portfolio", idempotency_key = "tagged"),
    "Entity",
    data.frame(
      preferred_name = "Project Firefly",
      tags = I(list(c("priority", "research"))),
      .graft_origin_key = "tagged",
      check.names = FALSE
    )
  )
  relations <- DBI::dbReadTable(store$connection, "entity__tags")

  expect_identical(result$inserted[["Entity"]], 1L)
  expect_setequal(relations$value, c("priority", "research"))
})

test_that("object relation migrations preserve referenced IDs everywhere", {
  schema <- kg_schema(tempest_manifest_path())
  store <- local_ingest_store(schema = schema)
  migrated <- migration_schema_add_object_relation(schema)
  plan <- kg_plan_migration(store, migrated)

  expect_in(
    "create_relation",
    vapply(plan$operations, \(.x) .x$kind, character(1))
  )
  kg_apply_migration(store, plan)

  target_id <- test_graft_id("object-relation-target")
  source_id <- test_graft_id("object-relation-source")
  kg_write(
    store,
    kg_batch("portfolio", idempotency_key = "object-target"),
    "Entity",
    data.frame(id = target_id, preferred_name = "Target")
  )
  kg_write(
    store,
    kg_batch("portfolio", idempotency_key = "object-source"),
    "Entity",
    data.frame(
      id = source_id,
      preferred_name = "Source",
      related_entities = I(list(target_id)),
      check.names = FALSE
    )
  )

  relation <- DBI::dbReadTable(
    store$connection,
    "entity__related_entities"
  )
  revision <- DBI::dbGetQuery(
    store$connection,
    paste0(
      "SELECT payload_json FROM _graft_record_revisions ",
      "WHERE record_id = ? ORDER BY revision_number DESC LIMIT 1"
    ),
    params = list(source_id)
  )
  payload <- jsonlite::fromJSON(
    revision$payload_json[[1L]],
    simplifyVector = FALSE
  )
  history <- kg_history(store, source_id, limit = 1)
  check <- kg_check_store(store, deep = TRUE)

  expect_identical(relation$subject, source_id)
  expect_identical(relation$object, target_id)
  expect_identical(
    unname(unlist(payload$related_entities, use.names = FALSE)),
    target_id
  )
  expect_identical(
    history$record[[1L]]$related_entities,
    target_id
  )
  expect_identical(check$valid, TRUE)
  expect_equal(check$reported_issues, 0L)
})

test_that("object relation migrations require VARCHAR reference slots", {
  schema <- kg_schema(tempest_manifest_path())
  store <- local_ingest_store(schema = schema)
  malformed <- migration_schema_add_object_relation(
    schema,
    relational_type = "DOUBLE"
  )

  condition <- tryCatch(
    kg_plan_migration(store, malformed),
    graft_error = identity
  )

  expect_s3_class(condition, "graft_schema_integrity_error")
  expect_identical(condition$rule, "object_reference_varchar")
  expect_length(
    intersect(
      "entity__related_entities",
      DBI::dbListTables(store$connection)
    ),
    0L
  )
})

test_that("added value relations must match the compiler contract", {
  schema <- kg_schema(tempest_manifest_path())
  store <- local_ingest_store(schema = schema)
  canonical <- migration_schema_add_relation(schema)
  relation_index <- length(canonical$manifest$relations)
  column_index <- function(relation, name) {
    which(vapply(
      relation$columns,
      \(.x) identical(.x$name, name),
      logical(1)
    ))[[1L]]
  }
  mutations <- list(
    value_type = function(relation) {
      relation$columns[[column_index(relation, "value")]]$type <- "DOUBLE"
      relation
    },
    owner_type = function(relation) {
      relation$columns[[column_index(relation, "owner_id")]]$type <- "BIGINT"
      relation
    },
    owner_nullability = function(relation) {
      relation$columns[[column_index(
        relation,
        "owner_id"
      )]]$nullable <- TRUE
      relation
    },
    owner_foreign_key = function(relation) {
      relation$columns[[column_index(
        relation,
        "owner_id"
      )]]$foreign_key$class <- "Claim"
      relation
    },
    extra_id_column = function(relation) {
      relation$columns <- c(
        list(list(
          name = "id",
          type = "VARCHAR",
          nullable = FALSE,
          primary_key = TRUE
        )),
        relation$columns
      )
      relation
    }
  )

  for (mutation in mutations) {
    tampered <- unserialize(serialize(canonical, NULL))
    relation <- tampered$manifest$relations[[relation_index]]
    tampered$manifest$relations[[relation_index]] <- mutation(relation)
    tampered <- migration_schema_finalize(tampered)

    condition <- tryCatch(
      kg_plan_migration(store, tampered),
      graft_error = identity
    )
    expect_s3_class(condition, "graft_schema_integrity_error")
  }
})

test_that("object relation columns and foreign keys are canonical", {
  schema <- kg_schema(tempest_manifest_path())
  canonical <- schema$manifest$relations[[1L]]
  column_index <- function(relation, name) {
    which(vapply(
      relation$columns,
      \(.x) identical(.x$name, name),
      logical(1)
    ))[[1L]]
  }
  mutations <- list(
    id_type = function(relation) {
      relation$columns[[column_index(relation, "id")]]$type <- "BIGINT"
      relation
    },
    id_primary_key = function(relation) {
      relation$columns[[column_index(
        relation,
        "id"
      )]]$primary_key <- FALSE
      relation
    },
    object_nullability = function(relation) {
      relation$columns[[column_index(
        relation,
        "object"
      )]]$nullable <- TRUE
      relation
    },
    object_foreign_key = function(relation) {
      relation$columns[[column_index(
        relation,
        "object"
      )]]$foreign_key$slot <- "not_id"
      relation
    },
    subject_foreign_key = function(relation) {
      relation$columns[[column_index(
        relation,
        "subject"
      )]]$foreign_key$class <- "Entity"
      relation
    },
    position_type = function(relation) {
      relation$columns[[column_index(
        relation,
        "position"
      )]]$type <- "VARCHAR"
      relation
    },
    created_at_type = function(relation) {
      relation$columns[[column_index(
        relation,
        "created_at"
      )]]$type <- "DATE"
      relation
    }
  )

  expect_identical(
    validate_new_relation_mapping(schema$manifest, "Claim", "about"),
    "Claim.about"
  )
  for (mutation in mutations) {
    tampered <- unserialize(serialize(schema$manifest, NULL))
    tampered$relations[[1L]] <- mutation(canonical)
    condition <- tryCatch(
      validate_new_relation_mapping(tampered, "Claim", "about"),
      graft_error = identity
    )
    expect_s3_class(condition, "graft_migration_unsupported")
  }

  tampered <- unserialize(serialize(schema$manifest, NULL))
  tampered$classes$Claim$slots$about$foreign_key$class <- "Entity"
  object_index <- column_index(tampered$relations[[1L]], "object")
  tampered$relations[[1L]]$columns[[object_index]]$foreign_key$class <-
    "Entity"
  condition <- tryCatch(
    validate_new_relation_mapping(tampered, "Claim", "about"),
    graft_error = identity
  )
  expect_s3_class(condition, "graft_migration_unsupported")
})

test_that("stale sensitivity digests cannot activate or expose stored data", {
  base <- kg_schema(tempest_manifest_path())
  sensitive <- migration_schema_copy(base, "sensitive-initial")
  sensitive$manifest$classes$Entity$slots$description$sensitive <- TRUE
  sensitive <- migration_schema_finalize(sensitive)
  store <- local_ingest_store(schema = sensitive)
  kg_write(
    store,
    kg_batch("portfolio", idempotency_key = "sensitive-entity"),
    "Entity",
    data.frame(
      preferred_name = "Project Firefly",
      description = "restricted concept",
      .graft_origin_key = "sensitive-entity",
      check.names = FALSE
    )
  )
  id <- DBI::dbReadTable(store$connection, "entity")$id[[1L]]
  relaxed <- migration_schema_copy(
    sensitive,
    "stale-sensitivity",
    structural = FALSE
  )
  relaxed$manifest$classes$Entity$slots$description$sensitive <- FALSE

  condition <- tryCatch(
    kg_plan_migration(store, relaxed),
    graft_error = identity
  )
  hydrated <- kg_get(store, id, include = character())

  expect_s3_class(condition, "graft_schema_integrity_error")
  expect_identical(condition$rule, "structural_digest_content_mismatch")
  expect_identical(store$schema$manifest, sensitive$manifest)
  expect_length(intersect("description", names(hydrated$record)), 0L)
  expect_identical(
    DBI::dbReadTable(store$connection, "entity")$description,
    "restricted concept"
  )
})

test_that("enum additions activate without physical DDL", {
  schema <- kg_schema(tempest_manifest_path())
  store <- local_ingest_store(schema = schema)
  migrated <- migration_schema_add_enum_value(schema)
  plan <- kg_plan_migration(store, migrated)
  tables_before <- DBI::dbListTables(store$connection)

  expect_identical(plan$classification, "additive")
  expect_in("enum_value_added", plan$changes$rule)
  expect_length(plan$operations, 0L)
  printed <- capture.output(print.kg_migration_plan(plan))
  expect_match(paste(printed, collapse = "\n"), "enum_value_added")
  kg_apply_migration(store, plan)

  expect_setequal(DBI::dbListTables(store$connection), tables_before)
  values <- kg_enums(store$schema)
  expect_in("urgent", subset(values, enum == "Importance")$value)
  migration <- DBI::dbReadTable(store$connection, "_graft_migrations")
  stored_changes <- jsonlite::fromJSON(
    migration$changes_json,
    simplifyVector = FALSE
  )
  expect_identical(stored_changes[[1L]]$rule, "enum_value_added")
})

test_that("scalar reference additions preserve fresh-store index parity", {
  schema <- kg_schema(tempest_manifest_path())
  store <- local_ingest_store(schema = schema)
  migrated <- migration_schema_add_reference_slot(schema)

  kg_apply_migration(store, kg_plan_migration(store, migrated))
  migrated_indexes <- DBI::dbGetQuery(
    store$connection,
    "SELECT index_name FROM duckdb_indexes() WHERE table_name = 'claim'"
  )$index_name
  fresh <- local_ingest_store(schema = migrated)
  fresh_indexes <- DBI::dbGetQuery(
    fresh$connection,
    "SELECT index_name FROM duckdb_indexes() WHERE table_name = 'claim'"
  )$index_name

  expect_in("graft_idx_claim_reviewed_by", migrated_indexes)
  expect_setequal(migrated_indexes, fresh_indexes)
})

test_that("no-op and structurally orphaned migrations are refused", {
  schema <- kg_schema(tempest_manifest_path())
  store <- local_ingest_store(schema = schema)
  no_op <- tryCatch(
    kg_plan_migration(store, schema),
    graft_error = identity
  )
  expect_s3_class(no_op, "graft_migration_noop")

  collision <- migration_schema_add_slot(schema, "collision")
  collision$manifest$fingerprints$build_digest <-
    schema$manifest$fingerprints$build_digest
  collision_condition <- tryCatch(
    kg_plan_migration(store, collision),
    graft_error = identity
  )
  expect_s3_class(collision_condition, "graft_migration_plan_error")

  orphan_table <- migration_schema_copy(schema, "orphan-table")
  orphan_table$manifest$tables$Orphan <- orphan_table$manifest$tables$Activity
  orphan_table$manifest$tables$Orphan$class <- "Orphan"
  orphan_table$manifest$tables$Orphan$name <- "orphan"
  orphan_table <- migration_schema_finalize(orphan_table)
  table_condition <- tryCatch(
    kg_plan_migration(store, orphan_table),
    graft_error = identity
  )
  expect_s3_class(table_condition, "graft_schema_integrity_error")

  orphan_column <- migration_schema_copy(schema, "orphan-column")
  orphan_column$manifest$tables$Entity$columns <- c(
    orphan_column$manifest$tables$Entity$columns,
    list(list(
      foreign_key = NULL,
      name = "orphan_column",
      nullable = TRUE,
      primary_key = FALSE,
      slot = "orphan_column",
      type = "VARCHAR"
    ))
  )
  orphan_column <- migration_schema_finalize(orphan_column)
  column_condition <- tryCatch(
    kg_plan_migration(store, orphan_column),
    graft_error = identity
  )
  expect_s3_class(column_condition, "graft_schema_integrity_error")

  orphan_projection <- migration_schema_copy(schema, "orphan-projection")
  orphan_projection$manifest$graph_projections$node_classes <- c(
    orphan_projection$manifest$graph_projections$node_classes,
    list("ImaginaryClass")
  )
  orphan_projection <- migration_schema_finalize(orphan_projection)
  projection_condition <- tryCatch(
    kg_plan_migration(store, orphan_projection),
    graft_error = identity
  )
  expect_s3_class(
    projection_condition,
    "graft_migration_unsupported"
  )

  malformed_relation <- migration_schema_add_relation(schema)
  malformed_relation$manifest$relations[[length(
    malformed_relation$manifest$relations
  )]]$kind <- "object"
  malformed_relation <- migration_schema_finalize(malformed_relation)
  relation_condition <- tryCatch(
    kg_plan_migration(store, malformed_relation),
    graft_error = identity
  )
  expect_s3_class(relation_condition, "graft_schema_integrity_error")
})

test_that("stale, tampered, read-only, and unsupported plans are refused", {
  path <- withr::local_tempfile(fileext = ".duckdb")
  schema <- kg_schema(tempest_manifest_path())
  store <- local_ingest_store(path = path, schema = schema)
  first_target <- migration_schema_copy(
    schema,
    "first-compatible",
    structural = FALSE
  )
  second_target <- migration_schema_copy(
    schema,
    "second-compatible",
    structural = FALSE
  )
  stale <- kg_plan_migration(store, first_target)
  current <- kg_plan_migration(store, second_target)
  tampered <- current
  tampered$classification <- "additive"
  changed_tamper <- current
  changed_tamper$changes <- data.frame(
    path = "/fabricated",
    object_type = "enum_value",
    change = "added",
    field = NA_character_,
    old_summary = NA_character_,
    new_summary = "fabricated",
    classification = "additive",
    rule = "fabricated_rule",
    stringsAsFactors = FALSE
  )

  tamper_condition <- tryCatch(
    kg_apply_migration(store, tampered),
    graft_error = identity
  )
  expect_s3_class(tamper_condition, "graft_migration_plan_error")
  changes_condition <- tryCatch(
    kg_apply_migration(store, changed_tamper),
    graft_error = identity
  )
  expect_s3_class(changes_condition, "graft_migration_plan_error")
  live <- current
  live$operations <- list(function() NULL)
  live_condition <- tryCatch(
    kg_apply_migration(store, live),
    graft_error = identity
  )
  expect_s3_class(live_condition, "graft_migration_plan_error")
  noncanonical <- current
  noncanonical$manifest_json <- paste0(" ", noncanonical$manifest_json)
  noncanonical_data <- unclass(noncanonical)[
    !names(noncanonical) %in%
      c(
        "plan_digest",
        "migration_id"
      )
  ]
  noncanonical$plan_digest <- migration_plan_digest(noncanonical_data)
  noncanonical$migration_id <- migration_id_from_digest(
    noncanonical$plan_digest
  )
  noncanonical_condition <- tryCatch(
    kg_apply_migration(store, noncanonical),
    graft_error = identity
  )
  expect_s3_class(
    noncanonical_condition,
    "graft_migration_plan_error"
  )

  kg_apply_migration(store, current)
  stale_condition <- tryCatch(
    kg_apply_migration(store, stale),
    graft_error = identity
  )
  expect_s3_class(stale_condition, "graft_migration_stale")

  unsupported <- migration_schema_add_slot(
    second_target,
    name = "required_decision",
    required = TRUE
  )
  unsupported_condition <- tryCatch(
    kg_plan_migration(store, unsupported),
    graft_error = identity
  )
  expect_s3_class(
    unsupported_condition,
    "graft_migration_unsupported"
  )

  read_only_plan <- kg_plan_migration(
    store,
    migration_schema_copy(
      second_target,
      "read-only",
      structural = FALSE
    )
  )
  kg_disconnect(store)
  read_only <- kg_connect_duckdb(second_target, path, read_only = TRUE)
  withr::defer(kg_disconnect(read_only))
  kg_init(read_only)
  read_only_condition <- tryCatch(
    kg_apply_migration(read_only, read_only_plan),
    graft_error = identity
  )
  expect_s3_class(read_only_condition, "graft_migration_read_only")
})

test_that("failed migration application rolls back every affected surface", {
  schema <- kg_schema(tempest_manifest_path())
  store <- local_ingest_store(schema = schema)
  migrated <- migration_schema_add_slot(schema, "rollback_note")
  plan <- kg_plan_migration(store, migrated)
  metadata_before <- DBI::dbReadTable(store$connection, "_graft_store")
  activations_before <- DBI::dbReadTable(
    store$connection,
    "_graft_schema_activations"
  )
  schema_before <- store$schema
  local_mocked_bindings(
    create_graph_views = function(...) stop("forced graph failure")
  )

  condition <- tryCatch(
    kg_apply_migration(store, plan),
    graft_error = identity
  )

  expect_s3_class(condition, "graft_backend_error")
  expect_length(
    intersect(
      "rollback_note",
      DBI::dbListFields(store$connection, "entity")
    ),
    0L
  )
  expect_identical(
    DBI::dbReadTable(store$connection, "_graft_store"),
    metadata_before
  )
  expect_identical(
    DBI::dbReadTable(store$connection, "_graft_schema_activations"),
    activations_before
  )
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_migrations")),
    0L
  )
  expect_identical(store$schema, schema_before)
  expect_in("_graft_nodes", DBI::dbListTables(store$connection))
})

test_that("a migrated file store reopens with the exact new manifest", {
  path <- withr::local_tempfile(fileext = ".duckdb")
  schema <- kg_schema(tempest_manifest_path())
  migrated <- migration_schema_add_slot(schema, "reopen_note")
  store <- kg_connect_duckdb(schema, path)
  kg_init(store)
  kg_apply_migration(store, kg_plan_migration(store, migrated))
  kg_disconnect(store)

  reopened <- kg_connect_duckdb(migrated, path)
  withr::defer(kg_disconnect(reopened))

  expect_invisible(kg_init(reopened))
  expect_in("reopen_note", DBI::dbListFields(reopened$connection, "entity"))
  expect_identical(
    kg_store_info(reopened)$active_build_digest,
    migrated$manifest$fingerprints$build_digest
  )
})
