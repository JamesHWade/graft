migration_schema_copy <- function(schema, suffix, structural = TRUE) {
  result <- unserialize(serialize(schema, NULL))
  fixture_digest <- function(kind) {
    paste0(
      "sha256:",
      digest::digest(
        paste("migration", suffix, kind, sep = ":"),
        algo = "sha256",
        serialize = FALSE
      )
    )
  }
  result$manifest$fingerprints$build_digest <- fixture_digest("build")
  result$manifest$fingerprints$source_digest <- fixture_digest("source")
  if (isTRUE(structural)) {
    result$manifest$fingerprints$structural_digest <-
      manifest_structural_digest(result$manifest)
  }
  result
}

migration_schema_finalize <- function(schema) {
  schema$manifest$fingerprints$structural_digest <-
    manifest_structural_digest(schema$manifest)
  schema
}

migration_schema_add_slot <- function(
  schema,
  name = "decision_note",
  required = FALSE
) {
  result <- migration_schema_copy(schema, paste0("slot-", name))
  slot <- result$manifest$classes$Entity$slots$description
  slot$name <- name
  slot$column <- name
  slot$required <- required
  result$manifest$classes$Entity$slots[[name]] <- slot
  result$manifest$slots[[name]] <- slot[names(
    result$manifest$slots$description
  )]
  result$manifest$tables$Entity$columns <- c(
    result$manifest$tables$Entity$columns,
    list(list(
      foreign_key = NULL,
      name = name,
      nullable = !required,
      primary_key = FALSE,
      slot = name,
      type = "VARCHAR"
    ))
  )
  migration_schema_finalize(result)
}

migration_schema_add_reference_slot <- function(schema) {
  result <- migration_schema_copy(schema, "reference-slot")
  slot <- result$manifest$classes$Claim$slots$primary_subject
  slot$name <- "reviewed_by"
  slot$column <- "reviewed_by"
  slot$required <- FALSE
  result$manifest$classes$Claim$slots$reviewed_by <- slot
  result$manifest$slots$reviewed_by <- slot[names(
    result$manifest$slots$primary_subject
  )]
  result$manifest$tables$Claim$columns <- c(
    result$manifest$tables$Claim$columns,
    list(list(
      foreign_key = slot$foreign_key,
      name = "reviewed_by",
      nullable = TRUE,
      primary_key = FALSE,
      slot = "reviewed_by",
      type = "VARCHAR"
    ))
  )
  migration_schema_finalize(result)
}

migration_schema_add_class <- function(schema) {
  result <- migration_schema_copy(schema, "class")
  contract <- result$manifest$classes$Entity
  contract$name <- "PortfolioItem"
  contract$table <- "portfolio_item"
  contract$type_uri <- "https://example.org/PortfolioItem"
  contract$origin_key_slots <- list()
  result$manifest$classes$PortfolioItem <- contract
  table <- result$manifest$tables$Entity
  table$class <- "PortfolioItem"
  table$name <- "portfolio_item"
  result$manifest$tables$PortfolioItem <- table
  result$manifest$graph_projections$node_classes <- as.list(sort(c(
    unlist(
      result$manifest$graph_projections$node_classes,
      use.names = FALSE
    ),
    "PortfolioItem"
  )))
  migration_schema_finalize(result)
}

migration_schema_add_relation <- function(schema) {
  result <- migration_schema_copy(schema, "relation")
  slot <- result$manifest$classes$Entity$slots$description
  slot$name <- "tags"
  slot$column <- NULL
  slot$multivalued <- TRUE
  slot$required <- FALSE
  result$manifest$classes$Entity$slots$tags <- slot
  result$manifest$classes$Entity$relations <- c(
    result$manifest$classes$Entity$relations,
    "Entity.tags"
  )
  global <- result$manifest$slots$description
  global$name <- "tags"
  global$multivalued <- TRUE
  result$manifest$slots$tags <- global
  result$manifest$relations <- c(
    result$manifest$relations,
    list(list(
      columns = list(
        list(
          foreign_key = list(class = "Entity", slot = "id"),
          name = "owner_id",
          nullable = FALSE,
          type = "VARCHAR"
        ),
        list(name = "position", nullable = TRUE, type = "BIGINT"),
        list(name = "value", nullable = FALSE, type = "VARCHAR")
      ),
      kind = "value",
      name = "Entity.tags",
      ordered = FALSE,
      owner_class = "Entity",
      owner_table = "entity",
      predicate = "https://example.org/tags",
      slot = "tags",
      table = "entity__tags"
    ))
  )
  migration_schema_finalize(result)
}

migration_schema_add_object_relation <- function(
  schema,
  relational_type = "VARCHAR"
) {
  result <- migration_schema_copy(schema, "object-relation")
  slot <- result$manifest$classes$Claim$slots$about
  slot$name <- "related_entities"
  slot$required <- FALSE
  slot$relational_type <- relational_type
  result$manifest$classes$Entity$slots$related_entities <- slot
  result$manifest$classes$Entity$relations <- c(
    result$manifest$classes$Entity$relations,
    "Entity.related_entities"
  )
  global <- result$manifest$slots$about
  global$name <- "related_entities"
  global$required <- FALSE
  global$relational_type <- relational_type
  result$manifest$slots$related_entities <- global
  result$manifest$relations <- c(
    result$manifest$relations,
    list(list(
      columns = generated_relation_columns("Entity", slot, "object"),
      kind = "object",
      name = "Entity.related_entities",
      ordered = FALSE,
      owner_class = "Entity",
      owner_table = "entity",
      predicate = "https://example.org/related_entities",
      slot = "related_entities",
      table = "entity__related_entities"
    ))
  )
  object_relations <- result$manifest$graph_projections$semantic_edges$object_relations
  result$manifest$graph_projections$semantic_edges$object_relations <-
    as.list(sort(c(
      empty_character(object_relations),
      "Entity.related_entities"
    )))
  migration_schema_finalize(result)
}

migration_schema_add_enum_value <- function(schema) {
  result <- migration_schema_copy(schema, "enum")
  result$manifest$enums$Importance$permissible_values <- c(
    result$manifest$enums$Importance$permissible_values,
    list(list(value = "urgent", meaning = NULL, description = NULL))
  )
  migration_schema_finalize(result)
}
