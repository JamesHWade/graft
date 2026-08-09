manifest_structural_contract <- function(manifest) {
  list(
    projection_mapping_version = manifest$projection_mapping_version,
    classes = manifest$classes,
    relations = manifest$relations,
    enums = manifest$enums,
    graph_projections = manifest$graph_projections,
    validation_invariants = manifest$validation_invariants,
    identifier_normalization_versions = manifest$identifier_normalization_versions
  )
}

manifest_structural_json <- function(manifest) {
  canonical_json(canonical_schema_value(
    manifest_structural_contract(manifest)
  ))
}

manifest_structural_digest <- function(manifest) {
  paste0(
    "sha256:",
    digest::digest(
      manifest_structural_json(manifest),
      algo = "sha256",
      serialize = FALSE
    )
  )
}

canonical_schema_value <- function(value) {
  if (!is.list(value) || is.null(value)) {
    return(value)
  }
  value_names <- names(value)
  if (!is.null(value_names) && all(nzchar(value_names))) {
    value <- value[order(value_names, method = "radix")]
  }
  lapply(value, canonical_schema_value)
}

schema_compatibility <- function(old_schema, new_schema) {
  if (!is_compiled_schema(old_schema) || !is_compiled_schema(new_schema)) {
    abort_schema_integrity(
      "Schema compatibility requires two compiled schemas."
    )
  }
  old_manifest <- old_schema$manifest
  new_manifest <- new_schema$manifest
  old_digest <- scalar_character(
    old_manifest$fingerprints$structural_digest
  )
  new_digest <- scalar_character(
    new_manifest$fingerprints$structural_digest
  )
  digests_valid <- identical(
    old_digest,
    manifest_structural_digest(old_manifest)
  ) &&
    identical(
      new_digest,
      manifest_structural_digest(new_manifest)
    )
  content_matches <- identical(
    manifest_structural_json(old_manifest),
    manifest_structural_json(new_manifest)
  )
  compatible <- digests_valid && content_matches

  list(
    compatible = compatible,
    classification = if (compatible) {
      "compatible"
    } else if (!digests_valid) {
      "invalid structural digest"
    } else {
      "structural change"
    },
    old_structural_digest = old_digest,
    new_structural_digest = new_digest
  )
}
