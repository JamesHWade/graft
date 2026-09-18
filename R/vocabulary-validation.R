# Validation and rendering of explicit vocabulary releases; no inferred semantics.
vocabulary_binding_error <- function(message) {
  stop(structure(
    list(message = message, call = NULL),
    class = c("graft_vocabulary_error", "error", "condition")
  ))
}

vocabulary_check_record <- function(x, fields, label) {
  if (!is.list(x) || !setequal(names(x), fields) || anyDuplicated(names(x))) {
    vocabulary_binding_error(paste(
      label,
      "has missing, duplicate, or unsupported fields"
    ))
  }
}

vocabulary_check_text <- function(x, label) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    vocabulary_binding_error(paste(label, "must be a nonempty string"))
  }
}

vocabulary_check_array <- function(x, label, empty = FALSE) {
  if (!is.list(x) || !is.null(names(x)) || (!empty && length(x) == 0L)) {
    vocabulary_binding_error(paste(label, "must be an array"))
  }
}

vocabulary_file_hash <- function(path) {
  digest::digest(file = path, algo = "sha256")
}

vocabulary_check_pinned_file <- function(root, ref) {
  vocabulary_check_text(ref$path, "path")
  vocabulary_check_text(ref$sha256, "sha256")
  if (
    !grepl("^[a-f0-9]{64}$", ref$sha256) ||
      basename(ref$path) != ref$path ||
      ref$path %in% c(".", "..") ||
      grepl("[\\\\/:]", ref$path)
  ) {
    vocabulary_binding_error(
      "Pinned files must be siblings with exact SHA-256 digests"
    )
  }
  path <- file.path(root, ref$path)
  bytes <- vocabulary_source_bytes(path)
  if (!identical(vocabulary_hash(bytes), ref$sha256)) {
    vocabulary_binding_error(paste(
      "Missing or changed pinned content:",
      ref$path
    ))
  }
  bytes
}

vocabulary_hash <- function(bytes) {
  digest::digest(bytes, algo = "sha256", serialize = FALSE)
}

vocabulary_source_bytes <- function(path) {
  vocabulary_check_text(path, "path")
  size <- file.info(path)$size
  if (
    !file.exists(path) ||
      dir.exists(path) ||
      is.na(size) ||
      size < 1 ||
      size > 1024^2
  ) {
    vocabulary_binding_error("Each source file must contain 1 byte to 1 MiB")
  }
  readBin(path, "raw", n = 1024^2 + 1L)
}

vocabulary_json <- function(bytes) {
  tryCatch(
    jsonlite::fromJSON(rawToChar(bytes), simplifyVector = FALSE),
    error = function(error) vocabulary_binding_error("Invalid vocabulary JSON")
  )
}

# Validate through upstream and consume its resolved export; never parse YAML.
vocabulary_parse_dictionary_export <- function(output) {
  json <- output[grepl("^\\{", output)]
  if (length(json) != 1L) {
    vocabulary_binding_error(
      "Expected one JSON document from data-dict export-spec"
    )
  }
  jsonlite::fromJSON(json, simplifyVector = FALSE)
}

vocabulary_read_dictionary <- function(bytes) {
  if (!requireNamespace("datadict", quietly = TRUE)) {
    vocabulary_binding_error(
      "Publishing requires the datadict package and its data-dict binary"
    )
  }
  path <- tempfile(fileext = ".yaml")
  on.exit(unlink(path), add = TRUE)
  writeBin(bytes, path)
  result <- tryCatch(
    {
      validated <- datadict::dd_run(c("validate-spec", path))
      exported <- datadict::dd_run(c("export-spec", path))
      list(validated = validated, exported = exported)
    },
    error = function(error) {
      vocabulary_binding_error(paste(
        "data-dict validation/export failed:",
        conditionMessage(error)
      ))
    }
  )
  validated <- result$validated
  exported <- result$exported
  list(
    model = vocabulary_parse_dictionary_export(exported$output),
    evidence = list(command = "validate-spec", status = validated$status),
    package_version = as.character(utils::packageVersion("datadict")),
    binary_sha256 = vocabulary_file_hash(datadict::dd_path())
  )
}

vocabulary_validate <- function(b, v, dictionaries) {
  vocabulary_check_record(
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
  if (!identical(b$format, "graft-bindings/1")) {
    vocabulary_binding_error("Unsupported bindings format")
  }
  vocabulary_check_text(b$release, "binding release")
  vocabulary_check_record(
    b$vocabulary,
    c("release", "path", "sha256"),
    "vocabulary reference"
  )
  lapply(b$vocabulary, vocabulary_check_text, label = "vocabulary reference")
  vocabulary_check_array(b$dictionaries, "dictionaries")
  vocabulary_check_array(b$bindings, "bindings")
  vocabulary_check_array(b$assertions, "assertions", empty = TRUE)
  vocabulary_check_record(v, c("format", "release", "terms"), "vocabulary")
  if (
    !identical(v$format, "graft-vocabulary/1") ||
      !identical(v$release, b$vocabulary$release)
  ) {
    vocabulary_binding_error("Vocabulary format or release mismatch")
  }
  vocabulary_check_text(v$release, "vocabulary release")
  vocabulary_check_array(v$terms, "terms")
  terms <- list()
  for (term in v$terms) {
    fields <- c("id", "kind", "definition", "aliases")
    if (identical(term$kind, "relationship")) {
      fields <- c(fields, "domain", "range")
    }
    vocabulary_check_record(term, fields, "term")
    lapply(
      term[c("id", "kind", "definition")],
      vocabulary_check_text,
      label = "term text"
    )
    if (identical(term$kind, "relationship")) {
      lapply(
        term[c("domain", "range")],
        vocabulary_check_text,
        label = "relationship endpoint"
      )
    }
    if (
      !term$kind %in% c("concept", "relationship") || !is.null(terms[[term$id]])
    ) {
      vocabulary_binding_error("Invalid term kind or duplicate stable ID")
    }
    vocabulary_check_array(term$aliases, "aliases", empty = TRUE)
    lapply(term$aliases, vocabulary_check_text, label = "alias")
    terms[[term$id]] <- term
  }
  for (term in terms) {
    if (term$kind == "relationship") {
      for (endpoint in c(term$domain, term$range)) {
        if (!identical(terms[[endpoint]]$kind, "concept")) {
          vocabulary_binding_error(
            "Relationship domain and range must name concepts"
          )
        }
      }
    }
  }
  dictionary_ids <- character()
  for (ref in b$dictionaries) {
    vocabulary_check_record(
      ref,
      c("id", "workflow", "path", "sha256"),
      "dictionary reference"
    )
    lapply(ref, vocabulary_check_text, label = "dictionary reference")
    if (ref$id %in% dictionary_ids) {
      vocabulary_binding_error("Duplicate dictionary ID")
    }
    dictionary_ids <- c(dictionary_ids, ref$id)
    if (is.null(dictionaries[[ref$id]]$model$tables)) {
      vocabulary_binding_error("Dictionary export must contain resolved tables")
    }
  }
  locate <- function(binding, field) {
    dict <- dictionaries[[binding$dictionary]]$model
    if (is.null(dict)) {
      vocabulary_binding_error("Unknown dictionary")
    }
    tables <- Filter(\(x) identical(x$name, binding$table), dict$tables)
    if (length(tables) != 1L) {
      vocabulary_binding_error("Missing or ambiguous bound table")
    }
    cols <- Filter(\(x) identical(x$name, field), tables[[1]]$columns)
    if (length(cols) != 1L) {
      vocabulary_binding_error(paste(
        "Missing or ambiguous bound field:",
        field
      ))
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
    vocabulary_check_record(binding, fields, "binding")
    lapply(binding, vocabulary_check_text, label = "binding field")
    if (binding$id %in% ids) {
      vocabulary_binding_error("Duplicate binding ID")
    }
    ids <- c(ids, binding$id)
    term <- terms[[binding$term]]
    if (is.null(term)) {
      vocabulary_binding_error("Unknown term")
    }
    if (!identical(term$kind, binding$kind)) {
      vocabulary_binding_error("Wrong binding kind")
    }
    if (binding$kind == "concept") {
      locate(binding, binding$field)
      key <- as.character(jsonlite::toJSON(
        binding[c("dictionary", "table", "field")],
        auto_unbox = TRUE
      ))
      if (key %in% concept_keys) {
        vocabulary_binding_error(
          "Ambiguous equivalence: multiple concepts for one field"
        )
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
            x$scope == binding$scope &&
            x$grain == binding$grain &&
            x$condition == binding$condition
        },
        b$bindings
      )
      if (length(hits) != 1L) {
        vocabulary_binding_error("Relationship direction/domain/range mismatch")
      }
    }
  }
  assertion_ids <- character()
  for (assertion in b$assertions) {
    vocabulary_check_record(
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
      vocabulary_binding_error("Duplicate assertion ID")
    }
    assertion_ids <- c(assertion_ids, assertion$id)
    lapply(
      assertion[setdiff(names(assertion), "negated")],
      vocabulary_check_text,
      label = "assertion field"
    )
    if (
      !identical(terms[[assertion$predicate]]$kind, "relationship") ||
        !assertion$status %in% c("draft", "accepted", "retracted") ||
        !is.logical(assertion$negated) ||
        length(assertion$negated) != 1L ||
        is.na(assertion$negated)
    ) {
      vocabulary_binding_error("Invalid assertion predicate or qualifiers")
    }
  }
  invisible(TRUE)
}

# One source of prose: every machine record, including qualifiers, is rendered.
vocabulary_render_context <- function(published) {
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
    "# Shared vocabulary",
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
