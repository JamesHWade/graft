graft_measure_class_name <- "GraftMeasure"
graft_measure_view_name <- "graft_measure"

graft_measure_slot <- function(
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

graft_measure_class_contract <- function() {
  list(
    ancestors = list(graft_measure_class_name, "GraftMetadata", "GraftRecord"),
    fixed_predicate = NULL,
    id_format = "linkml",
    id_policy = "require",
    is_a = "GraftMetadata",
    label_slot = "name",
    name = graft_measure_class_name,
    origin_key_slots = list(),
    qualifier_slots = list(),
    relations = list(),
    role = "metadata",
    search_slots = list("title", "description"),
    slots = list(
      id = graft_measure_slot(
        "id",
        range = "uriorcurie",
        required = TRUE,
        identifier = TRUE
      ),
      created_at = graft_measure_slot(
        "created_at",
        range = "datetime",
        duckdb_type = "TIMESTAMP"
      ),
      updated_at = graft_measure_slot(
        "updated_at",
        range = "datetime",
        duckdb_type = "TIMESTAMP"
      ),
      name = graft_measure_slot("name", required = TRUE),
      title = graft_measure_slot("title"),
      description = graft_measure_slot("description"),
      target_class = graft_measure_slot("target_class", required = TRUE),
      expr = graft_measure_slot("expr", required = TRUE),
      parameters = graft_measure_slot("parameters"),
      dimensions = graft_measure_slot("dimensions")
    ),
    statement_shape = NULL,
    type_uri = "https://w3id.org/graft/GraftMeasure",
    view = graft_measure_view_name
  )
}

augment_manifest_with_measures <- function(compiled) {
  manifest <- compiled$manifest
  if (!is.null(manifest$classes[[graft_measure_class_name]])) {
    return(compiled)
  }
  taken_views <- vapply(
    manifest$classes,
    \(class) scalar_character(class$view),
    character(1)
  )
  if (graft_measure_view_name %in% taken_views) {
    abort_schema_error(
      paste0(
        "The view name `",
        graft_measure_view_name,
        "` is reserved for the graft measure system class."
      ),
      field = "view",
      rule = "reserved_measure_view"
    )
  }
  manifest$classes[[graft_measure_class_name]] <- graft_measure_class_contract()
  manifest$fingerprints$structural_digest <- manifest_structural_digest(
    manifest
  )
  manifest$fingerprints$build_digest <- manifest_build_digest(manifest)
  compiled$manifest <- manifest
  compiled
}
