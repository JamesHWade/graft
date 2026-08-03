missing_slot_vector <- function(slot, n) {
  type <- validation_slot_type(slot)
  switch(
    type,
    BOOLEAN = rep(NA, n),
    BIGINT = rep(NA_character_, n),
    DECIMAL = rep(NA_character_, n),
    DOUBLE = rep(NA_real_, n),
    DATE = as.Date(rep(NA_character_, n)),
    TIMESTAMP = as.POSIXct(
      rep(NA_real_, n),
      origin = "1970-01-01",
      tz = "UTC"
    ),
    rep(NA_character_, n)
  )
}

validation_slot_type <- function(slot) {
  type <- toupper(scalar_character(slot$duckdb_type, "VARCHAR"))
  if (scalar_logical(slot$object_reference) && !identical(type, "VARCHAR")) {
    abort_schema_error(
      "Object-reference fields must use DuckDB type `VARCHAR`.",
      field = scalar_character(slot$name),
      rule = "object_reference_varchar",
      duckdb_type = type
    )
  }
  type
}

coerce_exact_numeric <- function(x, integer = FALSE) {
  if (is.factor(x)) {
    x <- as.character(x)
  }
  if (!is.numeric(x) && !is.character(x)) {
    return(NULL)
  }
  if (is.numeric(x)) {
    missing <- is.na(x)
    invalid <- !missing &
      (!is.finite(x) |
        x != trunc(x) |
        abs(x) > 2^53 - 1)
    if (any(invalid)) {
      return(NULL)
    }
    values <- rep(NA_character_, length(x))
    values[!missing] <- sprintf("%.0f", x[!missing])
    return(values)
  }
  values <- trimws(x)
  missing <- is.na(values)
  pattern <- if (integer) {
    "^[+-]?[0-9]+$"
  } else {
    "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)$"
  }
  if (any(!missing & !grepl(pattern, values, perl = TRUE))) {
    return(NULL)
  }
  result <- rep(NA_character_, length(values))
  result[!missing] <- vapply(
    values[!missing],
    canonical_exact_numeric_lexeme,
    character(1),
    decimal = !integer
  )
  result
}

canonical_exact_numeric_lexeme <- function(value, decimal) {
  negative <- startsWith(value, "-")
  unsigned <- sub("^[+-]", "", value)
  whole <- if (grepl(".", unsigned, fixed = TRUE)) {
    sub("\\..*$", "", unsigned)
  } else {
    unsigned
  }
  fraction <- if (decimal && grepl(".", unsigned, fixed = TRUE)) {
    sub("^[^.]*\\.", "", unsigned)
  } else {
    ""
  }
  whole <- sub("^0+", "", whole)
  if (!nzchar(whole)) {
    whole <- "0"
  }
  fraction <- sub("0+$", "", fraction)
  canonical <- paste0(
    whole,
    if (nzchar(fraction)) paste0(".", fraction) else ""
  )
  if (negative && !identical(canonical, "0")) {
    paste0("-", canonical)
  } else {
    canonical
  }
}

coerce_numeric <- function(x, integer = FALSE) {
  if (!is.numeric(x) && !is.character(x) && !is.factor(x)) {
    return(NULL)
  }
  original_missing <- is.na(x)
  value <- suppressWarnings(as.numeric(as.character(x)))
  invalid <- (!original_missing & is.na(value)) |
    is.nan(value) |
    is.infinite(value)
  if (any(invalid)) {
    return(NULL)
  }
  if (integer && any(!is.na(value) & value != trunc(value))) {
    return(NULL)
  }
  value
}

coerce_logical <- function(x) {
  if (is.logical(x)) {
    return(x)
  }
  if (is.numeric(x) && all(is.na(x) | x %in% c(0, 1))) {
    return(as.logical(x))
  }
  if (is.character(x) || is.factor(x)) {
    value <- tolower(as.character(x))
    valid <- is.na(value) | value %in% c("true", "false", "1", "0")
    if (!all(valid)) {
      return(NULL)
    }
    return(ifelse(is.na(value), NA, value %in% c("true", "1")))
  }
  NULL
}

coerce_date <- function(x) {
  if (inherits(x, "Date")) {
    return(x)
  }
  if (!is.character(x)) {
    return(NULL)
  }
  value <- suppressWarnings(as.Date(x))
  if (any(!is.na(x) & is.na(value))) {
    return(NULL)
  }
  value
}

coerce_timestamp <- function(x) {
  if (inherits(x, "POSIXt")) {
    return(as.POSIXct(x, tz = "UTC"))
  }
  if (inherits(x, "Date")) {
    return(as.POSIXct(x, tz = "UTC"))
  }
  if (!is.character(x)) {
    return(NULL)
  }
  value <- suppressWarnings(as.POSIXct(
    x,
    tz = "UTC",
    tryFormats = c(
      "%Y-%m-%dT%H:%M:%OSZ",
      "%Y-%m-%dT%H:%M:%OS%z",
      "%Y-%m-%d %H:%M:%OS",
      "%Y-%m-%d"
    )
  ))
  if (any(!is.na(x) & is.na(value))) {
    return(NULL)
  }
  value
}

coerce_time <- function(x) {
  if (!is.character(x)) {
    return(NULL)
  }
  valid <- is.na(x) |
    grepl("^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$", x)
  if (!all(valid)) {
    return(NULL)
  }
  x
}

is_missing_value <- function(value, multivalued = FALSE) {
  if (is.null(value) || length(value) == 0L || all(is.na(value))) {
    return(TRUE)
  }
  if (!multivalued && is.character(value) && !any(nzchar(trimws(value)))) {
    return(TRUE)
  }
  FALSE
}
