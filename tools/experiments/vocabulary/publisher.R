# Experiment-local publisher. No Graft store, chat, or expression evaluator.
binding_error <- function(message) {
  stop(structure(
    list(message = message, call = NULL),
    class = c("fixture_binding_error", "error", "condition")
  ))
}

check_record <- function(x, fields, label) {
  if (!is.list(x) || !setequal(names(x), fields) || anyDuplicated(names(x))) {
    binding_error(paste(label, "has missing, duplicate, or unsupported fields"))
  }
}

check_text <- function(x, label) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    binding_error(paste(label, "must be a nonempty string"))
  }
}

check_array <- function(x, label, empty = FALSE) {
  if (!is.list(x) || !is.null(names(x)) || (!empty && length(x) == 0L)) {
    binding_error(paste(label, "must be an array"))
  }
}

file_hash <- function(path) cli::hash_file_sha256(path)

read_json <- function(path) jsonlite::fromJSON(path, simplifyVector = FALSE)

check_pinned_file <- function(root, ref) {
  check_text(ref$path, "path")
  if (basename(ref$path) != ref$path || ref$path %in% c(".", "..")) {
    binding_error("Pinned files must be siblings of the companion artifact")
  }
  path <- file.path(root, ref$path)
  if (!file.exists(path) || !identical(file_hash(path), ref$sha256)) {
    binding_error(paste("Missing or changed pinned content:", ref$path))
  }
  path
}

# Validate through upstream and consume its resolved export; never parse YAML.
parse_dictionary_export <- function(output) {
  json <- output[grepl("^\\{", output)]
  if (length(json) != 1L) {
    binding_error("Expected one JSON document from data-dict export-spec")
  }
  jsonlite::fromJSON(json, simplifyVector = FALSE)
}

read_dictionary <- function(path) {
  validated <- datadict::dd_run(c("validate-spec", path))
  exported <- datadict::dd_run(c("export-spec", path))
  list(
    model = parse_dictionary_export(exported$output),
    evidence = list(command = "validate-spec", status = validated$status)
  )
}

publish_bindings <- function(path) {
  root <- dirname(path)
  b <- read_json(path)
  check_record(
    b,
    c(
      "format",
      "release",
      "vocabulary",
      "dictionaries",
      "bindings",
      "assertions"
    ),
    "bindings"
  )
  if (!identical(b$format, "graft-experiment-bindings/1")) {
    binding_error("Unsupported bindings format")
  }
  check_text(b$release, "binding release")
  check_record(
    b$vocabulary,
    c("release", "path", "sha256"),
    "vocabulary reference"
  )
  lapply(b$vocabulary, check_text, label = "vocabulary reference")
  check_array(b$dictionaries, "dictionaries")
  check_array(b$bindings, "bindings")
  check_array(b$assertions, "assertions", empty = TRUE)
  vpath <- check_pinned_file(root, b$vocabulary)
  v <- read_json(vpath)
  check_record(v, c("format", "release", "terms"), "vocabulary")
  if (
    !identical(v$format, "graft-experiment-vocabulary/1") ||
      !identical(v$release, b$vocabulary$release)
  ) {
    binding_error("Vocabulary format or release mismatch")
  }
  check_text(v$release, "vocabulary release")
  check_array(v$terms, "terms")
  terms <- list()
  for (term in v$terms) {
    fields <- c("id", "kind", "definition", "aliases")
    if (identical(term$kind, "relationship")) {
      fields <- c(fields, "domain", "range")
    }
    check_record(term, fields, "term")
    lapply(term[c("id", "kind", "definition")], check_text, label = "term text")
    if (identical(term$kind, "relationship")) {
      lapply(
        term[c("domain", "range")],
        check_text,
        label = "relationship endpoint"
      )
    }
    if (
      !term$kind %in% c("concept", "relationship") || !is.null(terms[[term$id]])
    ) {
      binding_error("Invalid term kind or duplicate stable ID")
    }
    check_array(term$aliases, "aliases", empty = TRUE)
    lapply(term$aliases, check_text, label = "alias")
    terms[[term$id]] <- term
  }
  for (term in terms) {
    if (term$kind == "relationship") {
      for (endpoint in c(term$domain, term$range)) {
        if (!identical(terms[[endpoint]]$kind, "concept")) {
          binding_error("Relationship domain and range must name concepts")
        }
      }
    }
  }
  dictionaries <- list()
  for (ref in b$dictionaries) {
    check_record(
      ref,
      c("id", "workflow", "path", "sha256"),
      "dictionary reference"
    )
    lapply(ref, check_text, label = "dictionary reference")
    if (!is.null(dictionaries[[ref$id]])) {
      binding_error("Duplicate dictionary ID")
    }
    dictionaries[[ref$id]] <- read_dictionary(check_pinned_file(root, ref))
  }
  locate <- function(binding, field) {
    dict <- dictionaries[[binding$dictionary]]$model
    if (is.null(dict)) {
      binding_error("Unknown dictionary")
    }
    tables <- Filter(\(x) identical(x$name, binding$table), dict$tables)
    if (length(tables) != 1L) {
      binding_error("Missing or ambiguous bound table")
    }
    cols <- Filter(\(x) identical(x$name, field), tables[[1]]$columns)
    if (length(cols) != 1L) {
      binding_error(paste("Missing or ambiguous bound field:", field))
    }
    cols[[1]]
  }
  ids <- character()
  concept_keys <- character()
  for (binding in b$bindings) {
    fields <- c(
      "id",
      "kind",
      "dictionary",
      "table",
      "term",
      "scope",
      "grain",
      "condition"
    )
    fields <- c(
      fields,
      if (identical(binding$kind, "concept")) "field" else c("from", "to")
    )
    check_record(binding, fields, "binding")
    lapply(binding, check_text, label = "binding field")
    if (binding$id %in% ids) {
      binding_error("Duplicate binding ID")
    }
    ids <- c(ids, binding$id)
    term <- terms[[binding$term]]
    if (is.null(term)) {
      binding_error("Unknown term")
    }
    if (!identical(term$kind, binding$kind)) {
      binding_error("Wrong binding kind")
    }
    if (binding$kind == "concept") {
      locate(binding, binding$field)
      key <- paste(binding$dictionary, binding$table, binding$field, sep = "/")
      if (key %in% concept_keys) {
        binding_error("Ambiguous equivalence: multiple concepts for one field")
      }
      concept_keys <- c(concept_keys, key)
    } else {
      locate(binding, binding$from)
      locate(binding, binding$to)
    }
  }
  for (binding in Filter(\(x) x$kind == "relationship", b$bindings)) {
    term <- terms[[binding$term]]
    for (endpoint in c("from", "to")) {
      expected <- if (endpoint == "from") term$domain else term$range
      hits <- Filter(
        function(x) {
          x$kind == "concept" &&
            x$dictionary == binding$dictionary &&
            x$table == binding$table &&
            x$field == binding[[endpoint]] &&
            x$term == expected &&
            x$scope == binding$scope
        },
        b$bindings
      )
      if (length(hits) != 1L) {
        binding_error("Relationship direction/domain/range mismatch")
      }
    }
  }
  assertion_ids <- character()
  for (assertion in b$assertions) {
    check_record(
      assertion,
      c(
        "id",
        "subject",
        "predicate",
        "object",
        "source",
        "status",
        "negated",
        "time",
        "scope"
      ),
      "assertion"
    )
    if (assertion$id %in% assertion_ids) {
      binding_error("Duplicate assertion ID")
    }
    assertion_ids <- c(assertion_ids, assertion$id)
    lapply(
      assertion[setdiff(names(assertion), "negated")],
      check_text,
      label = "assertion field"
    )
    if (
      !identical(terms[[assertion$predicate]]$kind, "relationship") ||
        !assertion$status %in% c("draft", "accepted", "retracted") ||
        !is.logical(assertion$negated) ||
        length(assertion$negated) != 1L ||
        is.na(assertion$negated)
    ) {
      binding_error("Invalid assertion predicate or qualifiers")
    }
  }
  references <- list(
    vocabulary = list(id = v$release, sha256 = file_hash(vpath)),
    bindings = list(id = b$release, sha256 = file_hash(path)),
    dictionaries = b$dictionaries
  )
  list(
    vocabulary = v,
    bindings = b,
    dictionaries = dictionaries,
    references = references
  )
}

# One source of prose: every machine record, including qualifiers, is rendered.
render_context <- function(published) {
  b <- published$bindings
  json <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, null = "null")
  binding_prose <- function(x) {
    location <- if (x$kind == "concept") x$field else paste(x$from, "->", x$to)
    paste0(
      "Binding `",
      x$id,
      "`: `",
      x$dictionary,
      "` table `",
      x$table,
      "` (`",
      location,
      "`) maps to ",
      x$kind,
      " `",
      x$term,
      "`. Scope: ",
      x$scope,
      "; grain: ",
      x$grain,
      "; condition: ",
      x$condition,
      "."
    )
  }
  assertion_prose <- function(x) {
    paste0(
      "Assertion `",
      x$id,
      "`: `",
      x$subject,
      "` -> `",
      x$predicate,
      "` -> `",
      x$object,
      "`. Status: ",
      x$status,
      "; negated: ",
      tolower(as.character(x$negated)),
      "; source: ",
      x$source,
      "; time: ",
      x$time,
      "; scope: ",
      x$scope,
      "."
    )
  }
  c(
    "# Shared laboratory vocabulary",
    paste("Vocabulary release:", published$vocabulary$release),
    paste("Binding release:", b$release),
    paste("Vocabulary SHA-256:", published$references$vocabulary$sha256),
    paste("Bindings SHA-256:", published$references$bindings$sha256),
    "Mappings support discovery. They do not authorize joins, comparison, access, or execution.",
    "Assertions retain direction and qualifiers. Retracted or negated assertions are not positive facts.",
    "## Terms",
    vapply(published$vocabulary$terms, json, character(1)),
    "## Exact dictionary references",
    vapply(b$dictionaries, json, character(1)),
    "## Binding explanations",
    vapply(b$bindings, binding_prose, character(1)),
    "## Assertion explanations",
    vapply(b$assertions, assertion_prose, character(1)),
    "## Exact binding records",
    vapply(b$bindings, json, character(1)),
    "## Exact qualified assertion records",
    vapply(b$assertions, json, character(1))
  )
}

# A real non-Commons caller: validate imported frame names, then expose a
# concept's local values with their source binding. No implicit cross-lab join.
import_concept <- function(published, workflow, frames, term) {
  refs <- Filter(\(x) x$workflow == workflow, published$bindings$dictionaries)
  if (length(refs) != 1L) {
    binding_error("Unknown workflow")
  }
  hits <- Filter(
    function(x) {
      x$kind == "concept" && x$dictionary == refs[[1]]$id && x$term == term
    },
    published$bindings$bindings
  )
  if (length(hits) != 1L) {
    binding_error("Concept lookup is absent or ambiguous")
  }
  hit <- hits[[1]]
  frame <- frames[[hit$table]]
  if (!is.data.frame(frame) || !hit$field %in% names(frame)) {
    binding_error("Imported data is missing its bound field")
  }
  list(
    values = frame[[hit$field]],
    binding = hit,
    references = published$references
  )
}

# Deliberately narrow comparison check, not a conversion, join planner, or
# general validator. Same term alone is insufficient, including identical IDs.
check_comparison <- function(published, left, right) {
  find <- function(id) {
    hits <- Filter(
      \(x) x$id == id && x$kind == "concept",
      published$bindings$bindings
    )
    if (length(hits) != 1L) {
      binding_error("Unknown comparison binding")
    }
    hits[[1]]
  }
  a <- find(left)
  b <- find(right)
  units <- function(x) {
    table <- Filter(
      \(t) t$name == x$table,
      published$dictionaries[[x$dictionary]]$model$tables
    )[[1]]
    Filter(\(c) c$name == x$field, table$columns)[[1]]$units
  }
  if (
    !identical(a$term, b$term) ||
      !identical(units(a), units(b)) ||
      !identical(a$grain, b$grain) ||
      !identical(a$condition, b$condition) ||
      !identical(a$scope, b$scope)
  ) {
    binding_error(
      "Comparison requires compatible term, units, grain, conditions, and identity scope"
    )
  }
  invisible(TRUE)
}
