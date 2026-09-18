# Validation and rendering of explicit vocabulary releases; no inferred semantics.
vocabulary_binding_error <- function(message) {
  graft_abort("graft_vocabulary_error", message, call = NULL)
}

vocabulary_check_object <- function(x, label) {
  if (
    !is.list(x) ||
      is.data.frame(x) ||
      is.null(names(x)) ||
      anyDuplicated(names(x))
  ) {
    vocabulary_binding_error(paste(
      label,
      "must be a JSON object with unique fields"
    ))
  }
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

vocabulary_check_pinned_reference <- function(ref) {
  vocabulary_check_object(ref, "file reference")
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
  invisible(ref)
}

vocabulary_check_pinned_file <- function(root, ref) {
  vocabulary_check_pinned_reference(ref)
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
  bytes <- tryCatch(
    readBin(path, "raw", n = 1024^2 + 1L),
    error = function(error) {
      vocabulary_binding_error("Could not read source file")
    }
  )
  if (length(bytes) < 1L || length(bytes) > 1024^2) {
    vocabulary_binding_error("Each source file must contain 1 byte to 1 MiB")
  }
  bytes
}

vocabulary_check_source_budget <- function(sizes, max_bytes) {
  if (anyNA(sizes) || any(sizes < 1L | sizes > 1024^2)) {
    vocabulary_binding_error("Each source file must contain 1 byte to 1 MiB")
  }
  if (sum(sizes) > max_bytes) {
    vocabulary_binding_error(
      "Source files exceed the artifact store's aggregate byte limit"
    )
  }
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
  vocabulary_json(charToRaw(json))
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
      binary_sha256 <- vocabulary_file_hash(datadict::dd_path())
      run <- function(command) {
        result <- vocabulary_dictionary_command(command, path)
        if (
          !identical(vocabulary_file_hash(datadict::dd_path()), binary_sha256)
        ) {
          vocabulary_binding_error(
            "The data-dict executable changed during validation/export"
          )
        }
        result
      }
      validated <- run("validate-spec")
      exported <- run("export-spec")
      list(
        validated = validated,
        exported = exported,
        binary_sha256 = binary_sha256
      )
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
    binary_sha256 = result$binary_sha256
  )
}

vocabulary_dictionary_command <- function(command, path) {
  datadict::dd_run(c(command, path))
}

vocabulary_companion <- function(b) {
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
  vocabulary_check_pinned_reference(b$vocabulary)
  vocabulary_check_array(b$dictionaries, "dictionaries")
  # Two artifacts per dictionary, three shared artifacts and one root must fit
  # the public artifact API's default traversal bound of 1,000 artifacts.
  if (length(b$dictionaries) > 498L) {
    vocabulary_binding_error(
      "A vocabulary release supports at most 498 dictionaries"
    )
  }
  vocabulary_check_array(b$bindings, "bindings")
  vocabulary_check_array(b$assertions, "assertions", empty = TRUE)
  ids <- character()
  for (ref in b$dictionaries) {
    vocabulary_check_record(
      ref,
      c("id", "workflow", "path", "sha256"),
      "dictionary reference"
    )
    lapply(ref, vocabulary_check_text, label = "dictionary reference")
    vocabulary_check_pinned_reference(ref)
    if (ref$id %in% ids) {
      vocabulary_binding_error("Duplicate dictionary ID")
    }
    ids <- c(ids, ref$id)
  }
  invisible(NULL)
}

vocabulary_validate <- function(b, v, dictionaries) {
  vocabulary_companion(b)
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
    vocabulary_check_object(term, "term")
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
    vocabulary_check_object(dictionaries[[ref$id]], "dictionary export")
    vocabulary_check_object(dictionaries[[ref$id]]$model, "dictionary model")
    if (is.null(dictionaries[[ref$id]]$model$tables)) {
      vocabulary_binding_error("Dictionary export must contain resolved tables")
    }
  }
  for (dictionary in dictionaries) {
    vocabulary_check_array(dictionary$model$tables, "dictionary tables")
    for (table in dictionary$model$tables) {
      vocabulary_check_object(table, "table")
      vocabulary_check_text(table$name, "table name")
      vocabulary_check_array(table$columns, "columns")
      for (column in table$columns) {
        vocabulary_check_object(column, "column")
        vocabulary_check_text(column$name, "column name")
      }
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
    vocabulary_check_object(binding, "binding")
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

# Quote release-controlled values as JSON code so Markdown treats them as data.
vocabulary_context_value <- function(x) {
  text <- as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"))
  runs <- gregexpr("`+", text)[[1L]]
  width <- max(0L, attr(runs, "match.length")) + 1L
  delimiter <- strrep("`", width)
  paste0(delimiter, " ", text, " ", delimiter)
}

# One source of prose: every machine record, including qualifiers, is rendered.
vocabulary_render_context <- function(published) {
  b <- published$bindings
  records <- function(x) {
    c(
      "```json",
      as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null")),
      "```"
    )
  }
  value <- vocabulary_context_value
  binding_prose <- function(x) {
    location <- if (x$kind == "concept") x$field else paste(x$from, "->", x$to)
    paste0(
      "Binding ",
      value(x$id),
      ": ",
      value(x$dictionary),
      " table ",
      value(x$table),
      " (",
      value(location),
      ") maps to ",
      x$kind,
      " ",
      value(x$term),
      ". Scope: ",
      value(x$scope),
      "; grain: ",
      value(x$grain),
      "; condition: ",
      value(x$condition),
      "."
    )
  }
  assertion_prose <- function(x) {
    paste0(
      "Assertion ",
      value(x$id),
      ": ",
      value(x$subject),
      " -> ",
      value(x$predicate),
      " -> ",
      value(x$object),
      ". Status: ",
      value(x$status),
      "; negated: ",
      tolower(as.character(x$negated)),
      "; source: ",
      value(x$source),
      "; time: ",
      value(x$time),
      "; scope: ",
      value(x$scope),
      "."
    )
  }
  c(
    "# Shared vocabulary",
    paste("Vocabulary release:", value(published$vocabulary$release)),
    paste("Binding release:", value(b$release)),
    paste("Vocabulary SHA-256:", published$references$vocabulary$sha256),
    paste("Bindings SHA-256:", published$references$bindings$sha256),
    "Mappings support discovery. They do not authorize joins, comparison, access, or execution.",
    "Assertions retain direction and qualifiers. Retracted or negated assertions are not positive facts.",
    "## Terms",
    records(published$vocabulary$terms),
    "## Exact dictionary references",
    records(b$dictionaries),
    "## Binding explanations",
    vapply(b$bindings, binding_prose, character(1)),
    "## Assertion explanations",
    vapply(b$assertions, assertion_prose, character(1)),
    "## Exact binding records",
    records(b$bindings),
    "## Exact qualified assertion records",
    records(b$assertions)
  )
}
