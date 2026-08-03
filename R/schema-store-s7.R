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
        any(!nzchar(data$search_slots)) ||
        anyDuplicated(data$search_slots)
    ) {
      return("@search_slots must contain unique non-empty strings")
    }
    if (
      !is.list(data$slots) ||
        is.null(names(data$slots)) ||
        any(!nzchar(names(data$slots))) ||
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
      getter = \(self) graft_store_state(self)$legacy$path
    ),
    read_only = S7::new_property(
      S7::class_logical,
      getter = \(self) graft_store_state(self)$legacy$read_only
    ),
    closed = S7::new_property(
      S7::class_logical,
      getter = function(self) {
        legacy <- graft_store_state(self)$legacy
        validate_kg_store(legacy, require_open = FALSE)
        isTRUE(legacy$closed)
      }
    ),
    capabilities = S7::new_property(
      S7::class_list,
      getter = \(self) as.list(graft_store_state(self)$legacy$capabilities)
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

#' Load a compiled Graft schema
#'
#' `graft_schema()` validates a compiled manifest and returns an immutable
#' semantic schema object. Its class and slot contracts describe the compiled
#' domain without creating runtime classes for domain records.
#'
#' @param path Path to a compiled `.graft.json` manifest.
#'
#' @return An immutable `GraftSchema` S7 object.
#' @export
graft_schema <- function(path) {
  new_graft_schema(kg_schema(path))
}

#' Open and initialize a Graft store
#'
#' `graft_open()` opens a DuckDB store and initializes a blank writable store or
#' verifies an existing store in one call. Graft closes connections it creates;
#' caller-supplied connections remain owned by the caller.
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
  legacy_schema <- as_graft_schema_internal(schema, "schema")
  validate_read_only(read_only)
  okf <- rlang::arg_match(okf)
  args <- list(
    schema = legacy_schema,
    read_only = read_only,
    connection = connection,
    okf = okf,
    okf_path = okf_path
  )
  if (is.null(connection) || !path_missing) {
    args$path <- path
  }
  legacy <- do.call(kg_connect_duckdb, args)
  tryCatch(
    {
      kg_init(legacy)
      metadata <- read_store_metadata(legacy$connection)
      state <- new.env(parent = emptyenv())
      state$legacy <- legacy
      state$schema <- schema
      state$id <- scalar_character(metadata$store_id)
      state$id_digest <- graft_sha256(canonical_json(state$id))
      GraftStore(state)
    },
    error = function(error) {
      kg_disconnect(legacy)
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
  legacy <- as_graft_store_internal(
    store,
    arg = "store",
    require_open = FALSE
  )
  kg_disconnect(legacy)
  invisible(store)
}

new_graft_schema <- function(schema) {
  validate_manifest_integrity(schema)
  state <- new.env(parent = emptyenv())
  state$manifest_json <- canonical_manifest_json(schema$manifest)
  state$path <- scalar_character(schema$path)
  state$classes <- graft_class_contracts(schema$manifest)
  GraftSchema(state)
}

as_graft_schema_object <- function(x, arg = rlang::caller_arg(x)) {
  if (S7::S7_inherits(x, GraftSchema)) {
    as_graft_schema_internal(x, arg)
    return(x)
  }
  if (inherits(x, "kg_schema")) {
    return(new_graft_schema(x))
  }
  abort_schema_error(
    paste0("`", arg, "` must be a GraftSchema object."),
    argument = arg
  )
}

as_graft_schema_internal <- function(x, arg = rlang::caller_arg(x)) {
  if (inherits(x, "kg_schema")) {
    validate_manifest_integrity(x)
    return(x)
  }
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
  schema <- new_kg_schema(graft_schema_manifest(x), path)
  validate_manifest_integrity(schema)
  schema
}

as_graft_store_internal <- function(
  x,
  arg = rlang::caller_arg(x),
  require_open = TRUE
) {
  if (is_kg_store(x)) {
    validate_kg_store(x, require_open = require_open, arg = arg)
    return(x)
  }
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
  legacy <- graft_store_state(x)$legacy
  validate_kg_store(legacy, require_open = require_open, arg = arg)
  legacy
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
    "external_identifier"
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
    external_identifier = scalar_character(slot$external_identifier)
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
  schema <- new_kg_schema(
    manifest,
    if (is.na(state$path)) NULL else state$path
  )
  integrity_error <- tryCatch(
    {
      validate_manifest_integrity(schema)
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
      sort(c("legacy", "schema", "id", "id_digest"))
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
  legacy <- state$legacy
  if (!is_kg_store(legacy)) {
    return("internal store state must contain a kg_store")
  }
  store_error <- tryCatch(
    {
      validate_kg_store(legacy, require_open = FALSE)
      NULL
    },
    error = conditionMessage
  )
  if (!is.null(store_error)) {
    return("internal kg_store state is invalid")
  }
  if (
    !is_scalar_flag(legacy$read_only) ||
      !is_scalar_flag(legacy$owns_connection) ||
      !is_scalar_flag(legacy$closed) ||
      !is_nonempty_string(legacy$path)
  ) {
    return("internal kg_store lifecycle fields are invalid")
  }
  expected_capabilities <- new_duckdb_capabilities(
    legacy$read_only,
    legacy$owns_connection
  )
  if (!identical(legacy$capabilities, expected_capabilities)) {
    return("@capabilities does not match the connection lifecycle")
  }
  legacy_schema <- tryCatch(
    {
      validate_manifest_integrity(legacy$schema)
      legacy$schema
    },
    error = identity
  )
  if (inherits(legacy_schema, "error")) {
    return("internal kg_store schema is invalid")
  }
  if (
    !identical(
      canonical_manifest_json(legacy_schema$manifest),
      graft_schema_state(state$schema)$manifest_json
    )
  ) {
    return("@schema does not match the store schema")
  }
  if (!isTRUE(legacy$closed)) {
    metadata <- tryCatch(
      read_store_metadata(legacy$connection),
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
