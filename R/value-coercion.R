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
    values[!missing & x == 0] <- "0"
    if (
      !all(vapply(
        values[!missing],
        exact_numeric_lexeme_fits_storage,
        logical(1),
        integer = integer
      ))
    ) {
      return(NULL)
    }
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
  if (
    !all(vapply(
      result[!missing],
      exact_numeric_lexeme_fits_storage,
      logical(1),
      integer = integer
    ))
  ) {
    return(NULL)
  }
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

exact_numeric_lexeme_fits_storage <- function(value, integer) {
  negative <- startsWith(value, "-")
  unsigned <- sub("^-", "", value)
  if (integer) {
    limit <- if (negative) {
      "9223372036854775808"
    } else {
      "9223372036854775807"
    }
    return(decimal_digits_less_than_or_equal(unsigned, limit))
  }
  parts <- strsplit(unsigned, ".", fixed = TRUE)[[1L]]
  whole <- parts[[1L]]
  fraction <- if (length(parts) == 1L) "" else parts[[2L]]
  nchar(whole) <= 15L && nchar(fraction) <= 3L
}

decimal_digits_less_than_or_equal <- function(value, limit) {
  value_length <- nchar(value)
  limit_length <- nchar(limit)
  if (value_length != limit_length) {
    return(value_length < limit_length)
  }
  value_digits <- utf8ToInt(value)
  limit_digits <- utf8ToInt(limit)
  difference <- which(value_digits != limit_digits)
  length(difference) == 0L ||
    value_digits[[difference[[1L]]]] < limit_digits[[difference[[1L]]]]
}

coerce_numeric <- function(x, integer = FALSE) {
  if (!is.numeric(x) && !is.character(x) && !is.factor(x)) {
    return(NULL)
  }
  original_missing <- is.na(x)
  text <- if (is.numeric(x)) NULL else as.character(x)
  value <- if (is.numeric(x)) {
    x
  } else {
    suppressWarnings(as.numeric(text))
  }
  underflow <- if (is.null(text)) {
    rep(FALSE, length(value))
  } else {
    significand <- sub("[eE].*$", "", trimws(text))
    !original_missing & value == 0 & grepl("[1-9]", significand)
  }
  invalid <- (!original_missing & is.na(value)) |
    is.nan(value) |
    is.infinite(value) |
    underflow
  if (any(invalid)) {
    return(NULL)
  }
  if (integer && any(!is.na(value) & value != trunc(value))) {
    return(NULL)
  }
  value[!is.na(value) & value == 0] <- 0
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

linkml_reference_patterns <- function() {
  pct_encoded <- "%[0-9A-Fa-f]{2}"
  unreserved <- "[A-Za-z0-9._~-]"
  sub_delims <- "[!$&'()*+,;=]"
  pchar <- paste0(
    "(?:",
    unreserved,
    "|",
    pct_encoded,
    "|",
    sub_delims,
    "|[:@])"
  )
  segment <- paste0(pchar, "*")
  segment_nz <- paste0(pchar, "+")
  segment_nz_nc <- paste0(
    "(?:",
    unreserved,
    "|",
    pct_encoded,
    "|",
    sub_delims,
    "|@)+"
  )
  reg_name <- paste0(
    "(?:",
    unreserved,
    "|",
    pct_encoded,
    "|",
    sub_delims,
    ")*"
  )
  userinfo <- paste0(
    "(?:",
    unreserved,
    "|",
    pct_encoded,
    "|",
    sub_delims,
    "|:)*"
  )
  dec_octet <- paste0(
    "(?:[0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])"
  )
  ipv4_address <- paste(rep(dec_octet, 4L), collapse = "\\.")
  h16 <- "[0-9A-Fa-f]{1,4}"
  ls32 <- paste0("(?:", h16, ":", h16, "|", ipv4_address, ")")
  ipv6_address <- paste0(
    "(?:",
    "(?:",
    h16,
    ":){6}",
    ls32,
    "|::(?:",
    h16,
    ":){5}",
    ls32,
    "|(?:",
    h16,
    ")?::(?:",
    h16,
    ":){4}",
    ls32,
    "|(?:(?:",
    h16,
    ":){0,1}",
    h16,
    ")?::(?:",
    h16,
    ":){3}",
    ls32,
    "|(?:(?:",
    h16,
    ":){0,2}",
    h16,
    ")?::(?:",
    h16,
    ":){2}",
    ls32,
    "|(?:(?:",
    h16,
    ":){0,3}",
    h16,
    ")?::",
    h16,
    ":",
    ls32,
    "|(?:(?:",
    h16,
    ":){0,4}",
    h16,
    ")?::",
    ls32,
    "|(?:(?:",
    h16,
    ":){0,5}",
    h16,
    ")?::",
    h16,
    "|(?:(?:",
    h16,
    ":){0,6}",
    h16,
    ")?::)"
  )
  ipv_future <- paste0(
    "v[0-9A-Fa-f]+\\.(?:",
    unreserved,
    "|",
    sub_delims,
    "|:)+"
  )
  ip_literal <- paste0("\\[(?:", ipv6_address, "|", ipv_future, ")\\]")
  host <- paste0("(?:", ip_literal, "|", ipv4_address, "|", reg_name, ")")
  authority <- paste0(
    "(?:",
    userinfo,
    "@)?",
    host,
    "(?::[0-9]*)?"
  )
  path_abempty <- paste0("(?:/", segment, ")*")
  path_absolute <- paste0(
    "/(?:",
    segment_nz,
    "(?:/",
    segment,
    ")*)?"
  )
  path_noscheme <- paste0(segment_nz_nc, "(?:/", segment, ")*")
  path_rootless <- paste0(segment_nz, "(?:/", segment, ")*")
  query <- paste0("(?:", pchar, "|[/?])*")
  scheme <- "[A-Za-z][A-Za-z0-9+.-]*"
  hier_part <- paste0(
    "(?://",
    authority,
    path_abempty,
    "|",
    path_absolute,
    "|",
    path_rootless,
    "|)"
  )
  relative_part <- paste0(
    "(?://",
    authority,
    path_abempty,
    "|",
    path_absolute,
    "|",
    path_noscheme,
    "|)"
  )
  suffix <- paste0("(?:\\?", query, ")?(?:#", query, ")?")
  uri <- paste0("^", scheme, ":", hier_part, suffix, "\\z")
  relative_ref <- paste0(relative_part, suffix)
  curie <- paste0(
    "^[A-Za-z_][A-Za-z0-9._-]*:",
    relative_ref,
    "\\z"
  )
  list(uri = uri, curie = curie)
}

linkml_reference_is_valid <- function(x, range = c("uri", "uriorcurie")) {
  range <- match.arg(range)
  if (!is.character(x)) {
    return(rep(FALSE, length(x)))
  }
  patterns <- linkml_reference_patterns()
  valid <- !is.na(x) & nzchar(x) & grepl(patterns$uri, x, perl = TRUE)
  if (identical(range, "uriorcurie")) {
    valid <- valid |
      (!is.na(x) &
        nzchar(x) &
        grepl(
          patterns$curie,
          x,
          perl = TRUE
        ))
  }
  valid
}

coerce_linkml_reference <- function(x, range = c("uri", "uriorcurie")) {
  range <- match.arg(range)
  if (is.factor(x)) {
    x <- as.character(x)
  }
  if (!is.character(x)) {
    return(NULL)
  }
  valid <- is.na(x) | linkml_reference_is_valid(x, range)
  if (!all(valid)) {
    return(NULL)
  }
  x
}

coerce_date <- function(x) {
  if (inherits(x, "Date")) {
    days <- as.numeric(x)
    rendered <- tryCatch(
      suppressWarnings(format(x, "%Y-%m-%d")),
      error = \(error) NULL
    )
    invalid <- is.null(rendered) ||
      length(rendered) != length(days) ||
      any(
        !is.na(days) &
          (!is.finite(days) |
            days != trunc(days) |
            is.na(rendered) |
            !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", rendered))
      )
    if (invalid) {
      return(NULL)
    }
    return(x)
  }
  if (!is.character(x)) {
    return(NULL)
  }
  valid_format <- is.na(x) |
    grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x)
  if (!all(valid_format)) {
    return(NULL)
  }
  value <- tryCatch(
    suppressWarnings(as.Date(x, format = "%Y-%m-%d")),
    error = \(error) NULL
  )
  if (is.null(value)) {
    return(NULL)
  }
  rendered <- format(value, "%Y-%m-%d")
  if (any(!is.na(x) & (is.na(value) | rendered != x))) {
    return(NULL)
  }
  value
}

coerce_timestamp <- function(x, datetime_format = NULL) {
  if (
    length(datetime_format) == 0L ||
      is.na(datetime_format) ||
      !nzchar(datetime_format)
  ) {
    datetime_format <- NULL
  }
  if (inherits(x, "POSIXt")) {
    value <- tryCatch(
      suppressWarnings(as.POSIXct(x, tz = "UTC")),
      error = \(error) NULL
    )
    if (is.null(value)) {
      return(NULL)
    }
    seconds <- as.numeric(value)
    whole_seconds <- trunc(seconds)
    microsecond_value <- whole_seconds +
      round((seconds - whole_seconds) * 1e6) / 1e6
    rendered <- tryCatch(
      suppressWarnings(format(
        value,
        "%Y-%m-%dT%H:%M:%S",
        tz = "UTC"
      )),
      error = \(error) NULL
    )
    invalid <- is.null(rendered) ||
      length(rendered) != length(seconds) ||
      any(
        !is.na(seconds) &
          (!is.finite(seconds) |
            seconds != microsecond_value |
            is.na(rendered) |
            !grepl(
              paste0(
                "^[0-9]{4}-[0-9]{2}-[0-9]{2}T",
                "[0-9]{2}:[0-9]{2}:[0-9]{2}$"
              ),
              rendered
            ))
      )
    if (invalid) {
      return(NULL)
    }
    return(value)
  }
  if (inherits(x, "Date")) {
    if (!is.null(datetime_format)) {
      return(NULL)
    }
    value <- coerce_date(x)
    if (is.null(value)) {
      return(NULL)
    }
    return(coerce_timestamp(as.POSIXct(value, tz = "UTC")))
  }
  if (!is.character(x)) {
    return(NULL)
  }
  if (!is.null(datetime_format)) {
    pattern <- switch(
      datetime_format,
      offset = offset_datetime_pattern(),
      local_utc = local_datetime_pattern(),
      NULL
    )
    if (is.null(pattern) || any(!is.na(x) & !grepl(pattern, x, perl = TRUE))) {
      return(NULL)
    }
  }
  seconds <- vapply(
    x,
    coerce_timestamp_character_value,
    numeric(1),
    datetime_format = datetime_format,
    USE.NAMES = FALSE
  )
  if (any(!is.na(x) & is.na(seconds))) {
    return(NULL)
  }
  as.POSIXct(seconds, origin = "1970-01-01", tz = "UTC")
}

coerce_timestamp_character_value <- function(value, datetime_format) {
  if (is.na(value)) {
    return(NA_real_)
  }
  offset <- identical(datetime_format, "offset") ||
    (is.null(datetime_format) &&
      grepl(offset_datetime_pattern(), value, perl = TRUE))
  local_utc <- identical(datetime_format, "local_utc") ||
    (is.null(datetime_format) &&
      grepl(local_datetime_pattern(), value, perl = TRUE))
  space_utc <- is.null(datetime_format) &&
    grepl(space_datetime_pattern(), value, perl = TRUE)
  date_utc <- is.null(datetime_format) &&
    grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", value, perl = TRUE)
  if (!offset && !local_utc && !space_utc && !date_utc) {
    return(NA_real_)
  }
  tryCatch(
    suppressWarnings({
      parsed <- if (offset) {
        match <- regexec(
          "([+-])([0-9]{2}):([0-9]{2})$",
          value,
          perl = TRUE
        )
        parts <- regmatches(value, match)[[1L]]
        if (length(parts) == 0L) {
          local_value <- sub("Z$", "", value)
          offset_seconds <- 0
        } else {
          local_value <- substr(value, 1L, nchar(value) - nchar(parts[[1L]]))
          direction <- if (identical(parts[[2L]], "+")) 1 else -1
          offset_seconds <- direction *
            (as.numeric(parts[[3L]]) * 3600 + as.numeric(parts[[4L]]) * 60)
        }
        local_time <- strptime(
          local_value,
          "%Y-%m-%dT%H:%M:%OS",
          tz = "UTC"
        )
        as.numeric(as.POSIXct(local_time, tz = "UTC")) - offset_seconds
      } else if (local_utc) {
        strptime(value, "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
      } else if (space_utc) {
        strptime(value, "%Y-%m-%d %H:%M:%OS", tz = "UTC")
      } else {
        strptime(value, "%Y-%m-%d", tz = "UTC")
      }
      as.numeric(as.POSIXct(
        parsed,
        origin = "1970-01-01",
        tz = "UTC"
      ))
    }),
    error = \(error) NA_real_
  )
}

offset_datetime_pattern <- function() {
  paste0(
    "^[0-9]{4}-[0-9]{2}-[0-9]{2}T",
    "(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]",
    "(?:\\.[0-9]{1,6})?(?:Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])$"
  )
}

local_datetime_pattern <- function() {
  paste0(
    "^[0-9]{4}-[0-9]{2}-[0-9]{2}T",
    "(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]",
    "(?:\\.[0-9]{1,6})?$"
  )
}

space_datetime_pattern <- function() {
  paste0(
    "^[0-9]{4}-[0-9]{2}-[0-9]{2} ",
    "(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]",
    "(?:\\.[0-9]{1,6})?$"
  )
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
