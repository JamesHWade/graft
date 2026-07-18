#' Compare two compiled graft schemas
#'
#' The structural digest determines compatibility. The returned report also
#' identifies class, slot, enum, table, and generated-relation changes so a
#' mismatch is useful to an interactive user or pipeline.
#'
#' @param old_schema A `kg_schema` object or manifest path.
#' @param new_schema A `kg_schema` object or manifest path.
#'
#' @return A `kg_schema_diff` object.
#' @export
kg_schema_diff <- function(old_schema, new_schema) {
  old_schema <- as_kg_schema(old_schema, "old_schema")
  new_schema <- as_kg_schema(new_schema, "new_schema")
  old <- old_schema$manifest
  new <- new_schema$manifest

  old_digest <- scalar_character(old$fingerprints$structural_digest)
  new_digest <- scalar_character(new$fingerprints$structural_digest)

  new_kg_schema_diff(
    old_structural_digest = old_digest,
    new_structural_digest = new_digest,
    classes = diff_named_contract(old$classes, new$classes),
    slots = diff_class_slots(old$classes, new$classes),
    enums = diff_named_contract(old$enums, new$enums),
    tables = diff_named_contract(old$tables, new$tables),
    relations = diff_relations(old$relations, new$relations)
  )
}

diff_named_contract <- function(old, new) {
  old_names <- names(old)
  new_names <- names(new)
  common <- intersect(old_names, new_names)
  changed <- common[
    !vapply(
      common,
      \(.x) identical(old[[.x]], new[[.x]]),
      logical(1)
    )
  ]
  list(
    added = sort(setdiff(new_names, old_names)),
    removed = sort(setdiff(old_names, new_names)),
    changed = sort(changed)
  )
}

diff_class_slots <- function(old_classes, new_classes) {
  common_classes <- intersect(names(old_classes), names(new_classes))
  rows <- lapply(common_classes, function(class) {
    old_slots <- old_classes[[class]]$slots
    new_slots <- new_classes[[class]]$slots
    old_names <- names(old_slots)
    new_names <- names(new_slots)
    common_slots <- intersect(old_names, new_names)
    changed <- common_slots[
      !vapply(
        common_slots,
        \(.x) identical(old_slots[[.x]], new_slots[[.x]]),
        logical(1)
      )
    ]
    data.frame(
      class = rep(
        class,
        length(setdiff(new_names, old_names)) +
          length(setdiff(old_names, new_names)) +
          length(changed)
      ),
      slot = c(
        sort(setdiff(new_names, old_names)),
        sort(setdiff(old_names, new_names)),
        sort(changed)
      ),
      change = c(
        rep("added", length(setdiff(new_names, old_names))),
        rep("removed", length(setdiff(old_names, new_names))),
        rep("changed", length(changed))
      ),
      row.names = NULL
    )
  })
  rows <- Filter(\(.x) nrow(.x) > 0L, rows)
  if (length(rows) == 0L) {
    return(data.frame(
      class = character(),
      slot = character(),
      change = character()
    ))
  }
  result <- do.call(rbind, rows)
  result[order(result$class, result$slot, result$change), , drop = FALSE]
}

diff_relations <- function(old, new) {
  relation_map <- function(relations) {
    if (length(relations) == 0L) {
      return(list())
    }
    names(relations) <- vapply(
      relations,
      \(.x) scalar_character(.x$name),
      character(1)
    )
    relations
  }
  diff_named_contract(relation_map(old), relation_map(new))
}
