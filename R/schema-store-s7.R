SlotContract <- S7::new_class(
  "SlotContract",
  package = "graft",
  properties = list(
    name = S7::new_property(
      S7::class_character,
      getter = \(self) slot_contract_data(self)$name
    ),
    range = S7::new_property(
      S7::class_character,
      getter = \(self) slot_contract_data(self)$range
    ),
    duckdb_type = S7::new_property(
      S7::class_character,
      getter = \(self) slot_contract_data(self)$duckdb_type
    ),
    required = S7::new_property(
      S7::class_logical,
      getter = \(self) slot_contract_data(self)$required
    ),
    multivalued = S7::new_property(
      S7::class_logical,
      getter = \(self) slot_contract_data(self)$multivalued
    ),
    sensitive = S7::new_property(
      S7::class_logical,
      getter = \(self) slot_contract_data(self)$sensitive
    ),
    object_reference = S7::new_property(
      S7::class_logical,
      getter = \(self) slot_contract_data(self)$object_reference
    ),
    identifier = S7::new_property(
      S7::class_logical,
      getter = \(self) slot_contract_data(self)$identifier
    ),
    external_identifier = S7::new_property(
      S7::class_character,
      getter = \(self) slot_contract_data(self)$external_identifier
    ),
    datetime_format = S7::new_property(
      S7::class_character,
      getter = \(self) slot_contract_data(self)$datetime_format
    )
  ),
  constructor = function(data) {
    S7::new_object(S7::S7_object(), .data = data)
  },
  validator = function(self) {
    data <- slot_contract_data(self)
    if (!identical(names(data), slot_contract_field_names())) {
      return("internal slot-contract fields are invalid")
    }
    if (!is_nonempty_string(data$name)) {
      return("@name must be one non-empty string")
    }
    if (!is_optional_string(data$range)) {
      return("@range must be one string or missing")
    }
    if (!is_nonempty_string(data$duckdb_type)) {
      return("@duckdb_type must be one non-empty string")
    }
    flags <- data[c(
      "required",
      "multivalued",
      "sensitive",
      "object_reference",
      "identifier"
    )]
    if (!all(vapply(flags, is_scalar_flag, logical(1)))) {
      return("slot-contract flags must each be TRUE or FALSE")
    }
    if (!is_optional_string(data$external_identifier)) {
      return("@external_identifier must be one string or missing")
    }
    if (
      !is_optional_string(data$datetime_format) ||
        (!is.na(data$datetime_format) &&
          !data$datetime_format %in% c("offset", "local_utc"))
    ) {
      return("@datetime_format must be offset, local_utc, or missing")
    }
    NULL
  }
)

ClassContract <- S7::new_class(
  "ClassContract",
  package = "graft",
  properties = list(
    name = S7::new_property(
      S7::class_character,
      getter = \(self) class_contract_data(self)$name
    ),
    role = S7::new_property(
      S7::class_character,
      getter = \(self) class_contract_data(self)$role
    ),
    abstract = S7::new_property(
      S7::class_logical,
      getter = \(self) class_contract_data(self)$abstract
    ),
    statement_shape = S7::new_property(
      S7::class_character,
      getter = \(self) class_contract_data(self)$statement_shape
    ),
    label_slot = S7::new_property(
      S7::class_character,
      getter = \(self) class_contract_data(self)$label_slot
    ),
    search_slots = S7::new_property(
      S7::class_character,
      getter = \(self) class_contract_data(self)$search_slots
    ),
    slots = S7::new_property(
      S7::class_list,
      getter = \(self) class_contract_data(self)$slots
    )
  ),
  constructor = function(data) {
    S7::new_object(S7::S7_object(), .data = data)
  },
  validator = function(self) {
    data <- class_contract_data(self)
    if (!identical(names(data), class_contract_field_names())) {
      return("internal class-contract fields are invalid")
    }
    if (!is_nonempty_string(data$name)) {
      return("@name must be one non-empty string")
    }
    if (!is_optional_string(data$role)) {
      return("@role must be one string or missing")
    }
    if (!is_scalar_flag(data$abstract)) {
      return("@abstract must be TRUE or FALSE")
    }
    if (
      !is_optional_string(data$statement_shape) ||
        !is_optional_string(data$label_slot)
    ) {
      return("statement and label fields must be one string or missing")
    }
    if (
      !is.character(data$search_slots) ||
        anyNA(data$search_slots) ||
        !all(nzchar(data$search_slots)) ||
        anyDuplicated(data$search_slots)
    ) {
      return("@search_slots must contain unique non-empty strings")
    }
    if (
      !is.list(data$slots) ||
        is.null(names(data$slots)) ||
        !all(nzchar(names(data$slots))) ||
        anyDuplicated(names(data$slots)) ||
        !all(vapply(
          data$slots,
          \(slot) S7::S7_inherits(slot, SlotContract),
          logical(1)
        ))
    ) {
      return("@slots must be a named list of SlotContract objects")
    }
    slot_errors <- lapply(data$slots, function(slot) {
      tryCatch(
        {
          S7::validate(slot)
          NULL
        },
        error = conditionMessage
      )
    })
    if (any(lengths(slot_errors) > 0L)) {
      return("@slots contains an invalid SlotContract object")
    }
    NULL
  }
)

GraftSchema <- S7::new_class(
  "GraftSchema",
  package = "graft",
  properties = list(
    name = S7::new_property(
      S7::class_character,
      getter = \(self) graft_schema_manifest(self)$schema$name
    ),
    version = S7::new_property(
      S7::class_character,
      getter = \(self) {
        scalar_character(
          graft_schema_manifest(self)$schema$version
        )
      }
    ),
    path = S7::new_property(
      S7::class_character,
      getter = \(self) graft_schema_state(self)$path
    ),
    digests = S7::new_property(
      S7::class_list,
      getter = \(self) graft_schema_manifest(self)$fingerprints
    ),
    structural_digest = S7::new_property(
      S7::class_character,
      getter = \(self) {
        scalar_character(
          graft_schema_manifest(self)$fingerprints$structural_digest
        )
      }
    ),
    source_digest = S7::new_property(
      S7::class_character,
      getter = \(self) {
        scalar_character(
          graft_schema_manifest(self)$fingerprints$source_digest
        )
      }
    ),
    build_digest = S7::new_property(
      S7::class_character,
      getter = \(self) {
        scalar_character(
          graft_schema_manifest(self)$fingerprints$build_digest
        )
      }
    ),
    classes = S7::new_property(
      S7::class_list,
      getter = \(self) graft_schema_state(self)$classes
    ),
    manifest = S7::new_property(
      S7::class_list,
      getter = function(self) graft_schema_manifest(self)
    )
  ),
  constructor = function(state) {
    S7::new_object(S7::S7_object(), .state = state)
  },
  validator = function(self) validate_graft_schema_s7(self)
)

GraftStore <- S7::new_class(
  "GraftStore",
  package = "graft",
  properties = list(
    id = S7::new_property(
      S7::class_character,
      getter = \(self) graft_store_state(self)$id
    ),
    path = S7::new_property(
      S7::class_character,
      getter = \(self) graft_store_state(self)$backend$path
    ),
    read_only = S7::new_property(
      S7::class_logical,
      getter = \(self) graft_store_state(self)$backend$read_only
    ),
    closed = S7::new_property(
      S7::class_logical,
      getter = function(self) {
        backend <- graft_store_state(self)$backend
        validate_store_backend(backend, require_open = FALSE)
        isTRUE(backend$closed)
      }
    ),
    capabilities = S7::new_property(
      S7::class_list,
      getter = \(self) as.list(graft_store_state(self)$backend$capabilities)
    ),
    schema = S7::new_property(
      S7::class_any,
      getter = \(self) graft_store_state(self)$schema
    )
  ),
  constructor = function(state) {
    S7::new_object(S7::S7_object(), .state = state)
  },
  validator = function(self) validate_graft_store_s7(self)
)

#' Load or compile a Graft schema
#'
#' `graft_schema()` turns a
#' [data-dict](https://data-dict.tidyverse.org/) or LinkML source into the
#' contract used to validate records, or loads an existing `.graft.json`
#' contract. A trusted resolved data-dict `export-spec` document compiles in R.
#' Data-dict YAML requires the optional `data-dict` CLI, while LinkML YAML
#' requires Python and `linkml-runtime`. When compiling a source contract
#' without `output`, Graft retains a temporary compiled manifest for the
#' returned schema object. Loading an existing `.graft.json` keeps its original
#' path.
#'
#' @param path Path to a data-dict YAML or resolved JSON contract, a LinkML YAML
#'   schema, or a compiled `.graft.json` manifest.
#' @param output Optional durable `.graft.json` output path when compiling a
#'   source contract.
#'
#' @return An immutable `GraftSchema` S7 object.
#' @examples
#' dictionary <- system.file(
#'   "extdata",
#'   "team-directory.data-dict.json",
#'   package = "graft",
#'   mustWork = TRUE
#' )
#' schema <- graft_schema(dictionary)
#' schema@name
#' @export
graft_schema <- function(path, output = NULL) {
  path <- normalize_graft_schema_path(path)
  lower <- tolower(path)
  if (endsWith(lower, ".graft.json")) {
    if (!is.null(output)) {
      abort_schema_error(
        "`output` is only supported when compiling a source contract.",
        argument = "output",
        schema_path = path
      )
    }
    return(new_graft_schema(load_schema_manifest(path)))
  }
  if (is_data_dict_document(path)) {
    output <- normalize_graft_schema_output(output)
    return(new_graft_schema(compile_data_dict_source(path, output)))
  }
  if (!grepl("\\.ya?ml$", lower)) {
    abort_schema_error(
      paste0(
        "Unsupported schema extension for `",
        path,
        "`; expected `.graft.json`, data-dict `.json`, `.yaml`, or `.yml`."
      ),
      argument = "path",
      schema_path = path
    )
  }
  output <- normalize_graft_schema_output(output)
  new_graft_schema(compile_schema_manifest(path, output))
}

normalize_graft_schema_path <- function(path) {
  if (!is_nonempty_string(path)) {
    abort_schema_error(
      "`path` must be one non-empty schema path.",
      argument = "path"
    )
  }
  if (!file.exists(path) || dir.exists(path)) {
    abort_schema_error(
      paste0("Schema file does not exist: `", path, "`."),
      argument = "path",
      schema_path = path
    )
  }
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

normalize_graft_schema_output <- function(output) {
  if (is.null(output)) {
    return(normalizePath(
      tempfile("graft-schema-", fileext = ".graft.json"),
      winslash = "/",
      mustWork = FALSE
    ))
  }
  if (!is_nonempty_string(output)) {
    abort_schema_error(
      "`output` must be one non-empty `.graft.json` path or `NULL`.",
      argument = "output"
    )
  }
  output <- path.expand(output)
  if (!endsWith(tolower(output), ".graft.json")) {
    abort_schema_error(
      "`output` must use the `.graft.json` extension.",
      argument = "output",
      output_path = output
    )
  }
  parent <- dirname(output)
  if (!dir.exists(parent)) {
    abort_schema_error(
      "The parent directory for `output` does not exist.",
      argument = "output",
      output_path = output
    )
  }
  output <- normalizePath(
    file.path(parent, basename(output)),
    winslash = "/",
    mustWork = FALSE
  )
  if (dir.exists(output)) {
    abort_schema_error(
      "`output` must be a file path, not a directory.",
      argument = "output",
      output_path = output
    )
  }
  output
}

#' Open and initialize a Graft store
#'
#' `graft_open()` creates a blank writable DuckDB store when `path` does not
#' exist, or verifies an existing store in one call. No pre-existing database
#' is required. Graft closes connections it creates; caller-supplied
#' connections remain owned by the caller.
#'
#' @param schema A `GraftSchema` object.
#' @param path DuckDB file path, or `":memory:"`.
#' @param read_only Whether the store must prohibit writes.
#' @param connection An optional existing DuckDB DBI connection.
#' @param okf Whether to manage an Open Knowledge Format working tree.
#' @param okf_path Optional managed OKF directory.
#'
#' @return A `GraftStore` S7 object ready for use.
#' @export
graft_open <- function(
  schema,
  path = ":memory:",
  read_only = FALSE,
  connection = NULL,
  okf = c("managed", "disabled"),
  okf_path = NULL
) {
  path_missing <- missing(path)
  schema <- as_graft_schema_object(schema, "schema")
  compiled_schema <- as_graft_schema_internal(schema, "schema")
  validate_read_only(read_only)
  okf <- rlang::arg_match(okf)
  args <- list(
    schema = compiled_schema,
    read_only = read_only,
    connection = connection,
    okf = okf,
    okf_path = okf_path
  )
  if (is.null(connection) || !path_missing) {
    args$path <- path
  }
  backend <- do.call(open_store_backend, args)
  tryCatch(
    {
      initialize_store_backend(backend)
      metadata <- read_store_metadata(backend$connection)
      state <- new.env(parent = emptyenv())
      state$backend <- backend
      state$schema <- schema
      state$id <- scalar_character(metadata$store_id)
      state$id_digest <- graft_sha256(canonical_json(state$id))
      GraftStore(state)
    },
    error = function(error) {
      close_store_backend(backend)
      stop(error)
    }
  )
}

#' Close a Graft store
#'
#' Closing is idempotent. Graft disconnects only connections it created; a
#' caller-supplied connection remains open.
#'
#' @param store A `GraftStore` object.
#'
#' @return `store`, invisibly.
#' @export
graft_close <- function(store) {
  backend <- as_graft_store_internal(
    store,
    arg = "store",
    require_open = FALSE
  )
  close_store_backend(backend)
  invisible(store)
}

new_graft_schema <- function(compiled_schema) {
  validate_manifest_integrity(compiled_schema)
  state <- new.env(parent = emptyenv())
  state$manifest_json <- canonical_manifest_json(compiled_schema$manifest)
  state$path <- scalar_character(compiled_schema$path)
  state$classes <- graft_class_contracts(compiled_schema$manifest)
  GraftSchema(state)
}

as_graft_schema_object <- function(x, arg = rlang::caller_arg(x)) {
  if (S7::S7_inherits(x, GraftSchema)) {
    as_graft_schema_internal(x, arg)
    return(x)
  }
  abort_schema_error(
    paste0("`", arg, "` must be a GraftSchema object."),
    argument = arg
  )
}

as_graft_schema_internal <- function(x, arg = rlang::caller_arg(x)) {
  if (!S7::S7_inherits(x, GraftSchema)) {
    abort_schema_error(
      paste0("`", arg, "` must be a GraftSchema object."),
      argument = arg
    )
  }
  error <- tryCatch(
    {
      S7::validate(x)
      NULL
    },
    error = identity
  )
  if (!is.null(error)) {
    abort_schema_integrity(
      paste0("`", arg, "` is an invalid GraftSchema object."),
      argument = arg,
      parent = error
    )
  }
  state <- graft_schema_state(x)
  path <- if (is.na(state$path)) NULL else state$path
  compiled_schema <- new_compiled_schema(graft_schema_manifest(x), path)
  validate_manifest_integrity(compiled_schema)
  compiled_schema
}

as_graft_store_internal <- function(
  x,
  arg = rlang::caller_arg(x),
  require_open = TRUE
) {
  if (!S7::S7_inherits(x, GraftStore)) {
    abort_backend_error(
      paste0("`", arg, "` must be a GraftStore object."),
      operation = "validate_store",
      argument = arg
    )
  }
  error <- tryCatch(
    {
      S7::validate(x)
      NULL
    },
    error = identity
  )
  if (!is.null(error)) {
    abort_backend_error(
      paste0("`", arg, "` is an invalid GraftStore object."),
      operation = "validate_store",
      argument = arg,
      parent = error
    )
  }
  backend <- graft_store_state(x)$backend
  validate_store_backend(backend, require_open = require_open, arg = arg)
  backend
}

slot_contract_field_names <- function() {
  c(
    "name",
    "range",
    "duckdb_type",
    "required",
    "multivalued",
    "sensitive",
    "object_reference",
    "identifier",
    "external_identifier",
    "datetime_format"
  )
}

class_contract_field_names <- function() {
  c(
    "name",
    "role",
    "abstract",
    "statement_shape",
    "label_slot",
    "search_slots",
    "slots"
  )
}

slot_contract_data <- function(x) {
  attr(x, ".data", exact = TRUE)
}

class_contract_data <- function(x) {
  attr(x, ".data", exact = TRUE)
}

is_nonempty_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
}

is_optional_string <- function(x) {
  is.character(x) && length(x) == 1L && (is.na(x) || nzchar(x))
}

is_scalar_flag <- function(x) {
  is.logical(x) && length(x) == 1L && !is.na(x)
}

graft_slot_contract <- function(name, slot) {
  SlotContract(list(
    name = name,
    range = scalar_character(slot$range),
    duckdb_type = scalar_character(slot$duckdb_type, "VARCHAR"),
    required = scalar_logical(slot$required),
    multivalued = scalar_logical(slot$multivalued),
    sensitive = scalar_logical(slot$sensitive),
    object_reference = scalar_logical(slot$object_reference),
    identifier = scalar_logical(slot$identifier),
    external_identifier = scalar_character(slot$external_identifier),
    datetime_format = scalar_character(slot$datetime_format)
  ))
}

graft_class_contract <- function(name, contract) {
  slots <- lapply(
    names(contract$slots),
    \(slot_name) graft_slot_contract(slot_name, contract$slots[[slot_name]])
  )
  names(slots) <- names(contract$slots)
  ClassContract(list(
    name = name,
    role = scalar_character(contract$role),
    abstract = scalar_logical(contract$abstract),
    statement_shape = scalar_character(contract$statement_shape),
    label_slot = scalar_character(contract$label_slot),
    search_slots = empty_character(contract$search_slots),
    slots = slots
  ))
}

graft_class_contracts <- function(manifest) {
  contracts <- lapply(
    names(manifest$classes),
    \(name) graft_class_contract(name, manifest$classes[[name]])
  )
  names(contracts) <- names(manifest$classes)
  contracts
}

graft_schema_state <- function(x) {
  state <- attr(x, ".state", exact = TRUE)
  if (!is.environment(state)) {
    abort_schema_integrity("GraftSchema internal state is invalid.")
  }
  state
}

graft_schema_manifest <- function(x) {
  state <- graft_schema_state(x)
  tryCatch(
    jsonlite::fromJSON(state$manifest_json, simplifyVector = FALSE),
    error = function(error) {
      abort_schema_integrity(
        "GraftSchema contains an invalid compiled manifest.",
        parent = error
      )
    }
  )
}

validate_graft_schema_s7 <- function(self) {
  state <- attr(self, ".state", exact = TRUE)
  if (!is.environment(state)) {
    return("internal schema state must be a private environment")
  }
  if (
    !identical(sort(ls(state)), sort(c("manifest_json", "path", "classes")))
  ) {
    return("internal schema state fields are invalid")
  }
  if (!is_nonempty_string(state$manifest_json)) {
    return("internal manifest must be canonical JSON")
  }
  if (!is_optional_string(state$path)) {
    return("@path must be one string or missing")
  }
  manifest <- tryCatch(
    jsonlite::fromJSON(state$manifest_json, simplifyVector = FALSE),
    error = identity
  )
  if (inherits(manifest, "error")) {
    return("internal manifest must be valid JSON")
  }
  if (!identical(canonical_manifest_json(manifest), state$manifest_json)) {
    return("internal manifest JSON must be canonical")
  }
  compiled_schema <- new_compiled_schema(
    manifest,
    if (is.na(state$path)) NULL else state$path
  )
  integrity_error <- tryCatch(
    {
      validate_manifest_integrity(compiled_schema)
      NULL
    },
    error = conditionMessage
  )
  if (!is.null(integrity_error)) {
    return("internal manifest failed integrity validation")
  }
  expected <- tryCatch(graft_class_contracts(manifest), error = identity)
  if (inherits(expected, "error") || !identical(state$classes, expected)) {
    return("@classes does not match the compiled manifest")
  }
  NULL
}

graft_store_state <- function(x) {
  state <- attr(x, ".state", exact = TRUE)
  if (!is.environment(state)) {
    abort_backend_error(
      "GraftStore internal state is invalid.",
      operation = "validate_store"
    )
  }
  state
}

validate_graft_store_s7 <- function(self) {
  state <- attr(self, ".state", exact = TRUE)
  if (!is.environment(state)) {
    return("internal store state must be a private environment")
  }
  if (
    !identical(
      sort(ls(state)),
      sort(c("backend", "schema", "id", "id_digest"))
    )
  ) {
    return("internal store state fields are invalid")
  }
  if (!is_nonempty_string(state$id)) {
    return("@id must be one non-empty string")
  }
  if (
    !is_graft_digest(state$id_digest) ||
      !identical(state$id_digest, graft_sha256(canonical_json(state$id)))
  ) {
    return("@id does not match its immutable identity digest")
  }
  if (!S7::S7_inherits(state$schema, GraftSchema)) {
    return("@schema must be a GraftSchema object")
  }
  schema_error <- tryCatch(
    {
      S7::validate(state$schema)
      NULL
    },
    error = conditionMessage
  )
  if (!is.null(schema_error)) {
    return("@schema is invalid")
  }
  backend <- state$backend
  if (!is_store_backend(backend)) {
    return("internal store state must contain a connection backend")
  }
  store_error <- tryCatch(
    {
      validate_store_backend(backend, require_open = FALSE)
      NULL
    },
    error = conditionMessage
  )
  if (!is.null(store_error)) {
    return("internal store backend is invalid")
  }
  if (
    !is_scalar_flag(backend$read_only) ||
      !is_scalar_flag(backend$owns_connection) ||
      !is_scalar_flag(backend$closed) ||
      !is_nonempty_string(backend$path)
  ) {
    return("internal store lifecycle fields are invalid")
  }
  expected_capabilities <- duckdb_capabilities(
    backend$read_only,
    backend$owns_connection
  )
  if (!identical(backend$capabilities, expected_capabilities)) {
    return("@capabilities does not match the connection lifecycle")
  }
  compiled_schema <- tryCatch(
    {
      validate_manifest_integrity(backend$schema)
      backend$schema
    },
    error = identity
  )
  if (inherits(compiled_schema, "error")) {
    return("internal store schema is invalid")
  }
  if (
    !identical(
      canonical_manifest_json(compiled_schema$manifest),
      graft_schema_state(state$schema)$manifest_json
    )
  ) {
    return("@schema does not match the store schema")
  }
  if (!isTRUE(backend$closed)) {
    metadata <- tryCatch(
      read_store_metadata(backend$connection),
      error = identity
    )
    if (
      inherits(metadata, "error") ||
        !identical(state$id, scalar_character(metadata$store_id))
    ) {
      return("@id does not match the initialized store")
    }
  }
  NULL
}
