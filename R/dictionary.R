#' Discover the public data dictionary at an accepted boundary
#'
#' `graft_dictionary()` exposes the accepted data-dict contract without record
#' values, examples, observed ranges, source locators, or restricted columns.
#' Public descriptive prose is not content-scrubbed; authors must keep private
#' information out of public descriptions and glossary entries.
#'
#' Entries follow document order, then adapter semantics. Each string cell is
#' capped at 2,000 characters. `text_truncated` marks clipped rows, and the outer
#' `truncated` flag also reports remaining pages. Narrow the selection or use
#' `next_offset` to retrieve another page. Selection uses dictionary names.
#' Dataset and glossary context is included with every selection; table and
#' column context is scoped. Relationships are included only when all endpoints
#' are public and at least one endpoint matches the selection. Only resolved
#' endpoint pairs and cardinality are shown: pairs do not encode join operators
#' or aliases, so discovery does not reconstruct a join expression.
#' Assertions require resolved public column references; dataset assertions
#' and assertions without resolved references are omitted.
#'
#' `supported` entries describe enforced contract properties. `descriptive`
#' entries are metadata, not executable assertions or acceptance constraints.
#' `unsupported` entries explain semantics outside Graft's supported profile.
#' Discovery is a generic read for [graft_verify()]: an explicit matching
#' quotation is required for cited evidence, and it is never calculation evidence.
#'
#' @param source An initialized `GraftStore` or immutable `GraftView` with a
#'   data-dict contract. Views retain their historical contract and receipt.
#' @param table Optional dictionary table name.
#' @param field Optional public column name; requires `table`.
#' @param limit Maximum entries to return, from 1 to 100.
#' @param offset Number of entries to skip, from 0 to 1,000,000.
#' @return A list with `result`, `truncated`, `limit`, and a canonical `receipt`.
#'   `result` contains an `entries` data frame, `total`, and `next_offset`
#'   (`NULL` on the last page). Entries have `kind`, `table`, `field`, `name`,
#'   `value`, `semantics`, and `text_truncated` columns. Compound values are JSON.
#' @export
graft_dictionary <- function(
  source,
  table = NULL,
  field = NULL,
  limit = 100L,
  offset = 0L
) {
  rlang::check_string(table, allow_null = TRUE)
  rlang::check_string(field, allow_null = TRUE)
  rlang::check_number_whole(limit, min = 1, max = 100)
  rlang::check_number_whole(offset, min = 0, max = 1000000)
  context <- graft_tool_context(source)
  backend <- as_graft_read_store_internal(context$store, "source")
  manifest <- backend$schema$manifest
  dictionary <- manifest$dictionary
  if (is.null(dictionary)) {
    abort_validation_error(
      "Dictionary discovery requires a data-dict contract.",
      field = "source",
      rule = "data_dict_required"
    )
  }
  public <- dictionary_public_fields(manifest)
  if (
    (!is.null(table) && !table %in% names(public)) ||
      (!is.null(field) && (is.null(table) || !field %in% public[[table]]))
  ) {
    abort_validation_error(
      "Select an available public dictionary table and column.",
      field = "table",
      rule = "dictionary_selection"
    )
  }
  entries <- dictionary_entries(dictionary, manifest, public, table, field)
  total <- nrow(entries)
  last <- min(total, offset + limit)
  indices <- if (offset < last) seq.int(offset + 1L, last) else integer()
  entries <- entries[indices, , drop = FALSE]
  rownames(entries) <- NULL
  graft_tool_result(
    list(
      entries = entries,
      total = total,
      next_offset = if (last < total) as.integer(last) else NULL
    ),
    truncated = last < total || any(entries$text_truncated),
    limit = as.integer(limit),
    receipt = context$receipt
  )
}

dictionary_public_fields <- function(manifest) {
  tables <- manifest$dictionary$document$tables
  stats::setNames(
    lapply(tables, function(table) {
      slots <- manifest$classes[[table$name]]$slots
      names(Filter(\(slot) !isTRUE(slot$sensitive), slots))
    }),
    vapply(tables, `[[`, "", "name")
  )
}

dictionary_entries <- function(dictionary, manifest, public, table, field) {
  rows <- list()
  add <- function(
    kind,
    table = "",
    field = "",
    name,
    value,
    semantics = "descriptive"
  ) {
    if (is.null(value)) {
      return(invisible(NULL))
    }
    value <- if (is.character(value) && length(value) == 1L) {
      value
    } else {
      canonical_json(value)
    }
    cells <- c(
      kind = kind,
      table = table,
      field = field,
      name = name,
      value = value,
      semantics = semantics
    )
    clipped <- any(nchar(cells, type = "chars") > 2000L)
    row <- as.list(substring(cells, 1L, 2000L))
    row$text_truncated <- clipped
    rows[[length(rows) + 1L]] <<- as.data.frame(row, stringsAsFactors = FALSE)
    invisible(NULL)
  }
  prose <- c("name", "label", "description", "details")
  document <- dictionary$document
  for (key in prose) {
    add("dataset", name = key, value = document[[key]])
  }
  for (item in document$tables) {
    if (!is.null(table) && !identical(table, item$name)) {
      next
    }
    for (key in prose) {
      add("table", item$name, name = key, value = item[[key]])
    }
    add(
      "table",
      item$name,
      name = "assertions",
      value = dictionary_public_assertions(item$assertions, public[[item$name]])
    )
    for (column in item$columns) {
      if (!column$name %in% public[[item$name]]) {
        next
      }
      if (!is.null(field) && !identical(field, column$name)) {
        next
      }
      for (key in c(prose, "unit", "units", "measure", "type", "constraints")) {
        add("column", item$name, column$name, key, column[[key]])
      }
      add(
        "column",
        item$name,
        column$name,
        "assertions",
        dictionary_public_assertions(column$assertions, public[[item$name]])
      )
      slot <- manifest$classes[[item$name]]$slots[[column$name]]
      for (key in c(
        "range",
        "required",
        "multivalued",
        "identifier",
        "object_reference",
        "pattern",
        "minimum_value",
        "maximum_value"
      )) {
        add("contract", item$name, column$name, key, slot[[key]], "supported")
      }
    }
  }
  for (relationship in document$relationships) {
    relationship$pairs <- lapply(relationship$pairs, function(pair) {
      lapply(pair[c("left", "right")], function(endpoint) {
        endpoint[c("table", "column")]
      })
    })
    endpoints <- unlist(
      lapply(relationship$pairs, \(pair) unname(pair)),
      recursive = FALSE
    )
    if (length(endpoints) == 0L) {
      next
    }
    visible <- vapply(
      endpoints,
      function(endpoint) {
        is.character(endpoint$table) &&
          is.character(endpoint$column) &&
          endpoint$column %in% public[[endpoint$table]]
      },
      logical(1)
    )
    selected <- vapply(
      endpoints,
      function(endpoint) {
        (is.null(table) || identical(table, endpoint$table)) &&
          (is.null(field) || identical(field, endpoint$column))
      },
      logical(1)
    )
    if (!all(visible) || !any(selected)) {
      next
    }
    for (key in c("pairs", "cardinality", "description")) {
      add("relationship", name = key, value = relationship[[key]])
    }
  }
  for (item in document$glossary) {
    add("glossary", name = item$term, value = item$definition)
  }
  for (name in names(dictionary$not_enforced)) {
    item <- dictionary$not_enforced[[name]]
    status <- if (
      item$status %in% c("not expressible", "not mapped", "not accepted")
    ) {
      "unsupported"
    } else {
      "descriptive"
    }
    add("semantics", name = name, value = item, semantics = status)
  }
  do.call(rbind, rows)
}

dictionary_public_assertions <- function(assertions, public) {
  assertions <- Filter(
    function(assertion) {
      columns <- unlist(assertion$columns, use.names = FALSE)
      is.character(columns) && length(columns) > 0L && all(columns %in% public)
    },
    assertions
  )
  if (length(assertions) == 0L) {
    return(NULL)
  }
  lapply(assertions, function(assertion) {
    assertion[intersect(
      c("expression", "description", "columns"),
      names(assertion)
    )]
  })
}
