definition_expr_aggregates <- c(
  "MIN",
  "MAX",
  "SUM",
  "AVG",
  "COUNT",
  "ROW_COUNT",
  "COUNT_DISTINCT",
  "ANY",
  "ALL"
)
definition_expr_functions <- c(
  "LENGTH",
  "LOWER",
  "UPPER",
  "TRIM",
  "STARTS_WITH",
  "ENDS_WITH",
  "ABS",
  "FLOOR",
  "CEIL",
  "ROUND",
  "MOD",
  "IS_FINITE",
  "IS_INFINITE",
  "IS_NAN",
  definition_expr_aggregates
)

definition_expr_arities <- list(
  LENGTH = 1L,
  LOWER = 1L,
  UPPER = 1L,
  TRIM = 1L,
  STARTS_WITH = 2L,
  ENDS_WITH = 2L,
  ABS = 1L,
  FLOOR = 1L,
  CEIL = 1L,
  ROUND = 1:2,
  MOD = 2L,
  IS_FINITE = 1L,
  IS_INFINITE = 1L,
  IS_NAN = 1L,
  MIN = 1L,
  MAX = 1L,
  SUM = 1L,
  AVG = 1L,
  COUNT = 1L,
  ROW_COUNT = 0L,
  COUNT_DISTINCT = 1L,
  ANY = 1L,
  ALL = 1L
)

definition_expr_no_issues <- function() {
  data.frame(
    rule = character(),
    message = character(),
    stringsAsFactors = FALSE
  )
}

definition_expr_issue <- function(rule, message) {
  data.frame(rule = rule, message = message, stringsAsFactors = FALSE)
}

definition_expr_check <- function(expr, columns, selection_columns = columns) {
  tokens <- tryCatch(
    definition_expr_tokenize(expr),
    graft_definition_expr_error = \(condition) condition
  )
  if (rlang::is_condition(tokens)) {
    return(list(
      issues = definition_expr_issue(
        "definition_expr_parse",
        conditionMessage(tokens)
      ),
      sql = NA_character_,
      selection = NULL
    ))
  }
  state <- new.env(parent = emptyenv())
  state$tokens <- tokens
  state$position <- 1L
  state$issues <- definition_expr_no_issues()
  state$columns <- columns
  state$selection_columns <- selection_columns
  state$selection <- NULL
  sql <- tryCatch(
    {
      out <- definition_expr_parse_or(state)
      remaining <- definition_expr_peek(state)
      if (!is.null(remaining)) {
        definition_expr_abort(paste0(
          "Unexpected `",
          remaining$text,
          "` after end of expression."
        ))
      }
      if (is.null(state$selection)) {
        out
      } else {
        expanded <- vapply(
          state$selection,
          function(column) {
            sub(
              definition_expr_selection_marker,
              paste0('"', gsub('"', '""', column, fixed = TRUE), '"'),
              out,
              fixed = TRUE
            )
          },
          character(1)
        )
        if (grepl("\\b(AND|OR)\\b", out)) {
          expanded <- paste0("(", expanded, ")")
        }
        paste(expanded, collapse = " AND ")
      }
    },
    graft_definition_expr_error = \(condition) {
      state$issues <- rbind(
        state$issues,
        definition_expr_issue(
          "definition_expr_parse",
          conditionMessage(condition)
        )
      )
      NA_character_
    }
  )
  if (nrow(state$issues) > 0L) {
    sql <- NA_character_
  }
  list(issues = state$issues, sql = sql, selection = state$selection)
}

definition_expr_selection_marker <- "__GRAFT_SELECTED_COLUMN__"

definition_expr_abort <- function(message) {
  rlang::abort(message, class = "graft_definition_expr_error")
}

definition_expr_tokenize <- function(expr) {
  if (!is_nonempty_string(expr)) {
    definition_expr_abort(
      "A definition expression must be one non-empty string."
    )
  }
  source <- expr
  tokens <- list()
  while (nzchar(source)) {
    whitespace <- regmatches(source, regexpr("^\\s+", source))
    if (length(whitespace) == 1L) {
      source <- substr(source, nchar(whitespace) + 1L, nchar(source))
      next
    }
    matched <- FALSE
    for (spec in list(
      c("number", "^[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?"),
      c("string", "^'([^']|'')*'"),
      c("quoted_identifier", "^`([^`]|``)*`"),
      c("identifier", "^[A-Za-z_][A-Za-z0-9_]*"),
      c("operator", "^(<>|!=|<=|>=|[=<>+*/()-])"),
      c("comma", "^,"),
      c("dot", "^\\."),
      c("bracket", "^(\\[|\\])")
    )) {
      text <- regmatches(source, regexpr(spec[[2L]], source))
      if (length(text) == 1L) {
        tokens[[length(tokens) + 1L]] <- list(type = spec[[1L]], text = text)
        source <- substr(source, nchar(text) + 1L, nchar(source))
        matched <- TRUE
        break
      }
    }
    if (!matched) {
      definition_expr_abort(paste0(
        "Unexpected character `",
        substr(source, 1L, 1L),
        "` in definition expression."
      ))
    }
  }
  if (length(tokens) == 0L) {
    definition_expr_abort(
      "A definition expression must be one non-empty string."
    )
  }
  tokens
}

definition_expr_peek <- function(state) {
  if (state$position > length(state$tokens)) {
    return(NULL)
  }
  state$tokens[[state$position]]
}

definition_expr_advance <- function(state) {
  token <- definition_expr_peek(state)
  state$position <- state$position + 1L
  token
}

definition_expr_expect <- function(state, text) {
  token <- definition_expr_peek(state)
  if (is.null(token) || !identical(toupper(token$text), toupper(text))) {
    observed <- if (is.null(token)) {
      "end of expression"
    } else {
      paste0("`", token$text, "`")
    }
    definition_expr_abort(paste0(
      "Expected `",
      text,
      "` but found ",
      observed,
      "."
    ))
  }
  definition_expr_advance(state)
}

definition_expr_keyword <- function(token, keyword) {
  !is.null(token) &&
    identical(token$type, "identifier") &&
    identical(toupper(token$text), keyword)
}

definition_expr_parse_or <- function(state) {
  left <- definition_expr_parse_and(state)
  while (definition_expr_keyword(definition_expr_peek(state), "OR")) {
    definition_expr_advance(state)
    left <- paste(left, "OR", definition_expr_parse_and(state))
  }
  left
}

definition_expr_parse_and <- function(state) {
  left <- definition_expr_parse_not(state)
  while (definition_expr_keyword(definition_expr_peek(state), "AND")) {
    definition_expr_advance(state)
    left <- paste(left, "AND", definition_expr_parse_not(state))
  }
  left
}

definition_expr_parse_not <- function(state) {
  if (definition_expr_keyword(definition_expr_peek(state), "NOT")) {
    definition_expr_advance(state)
    return(paste("NOT", definition_expr_parse_not(state)))
  }
  definition_expr_parse_comparison(state)
}

definition_expr_parse_comparison <- function(state) {
  left <- definition_expr_parse_additive(state)
  token <- definition_expr_peek(state)
  if (
    !is.null(token) &&
      identical(token$type, "operator") &&
      token$text %in% c("=", "!=", "<>", "<", "<=", ">", ">=")
  ) {
    definition_expr_advance(state)
    return(paste(left, token$text, definition_expr_parse_additive(state)))
  }
  if (definition_expr_keyword(token, "IS")) {
    definition_expr_advance(state)
    negated <- FALSE
    if (definition_expr_keyword(definition_expr_peek(state), "NOT")) {
      definition_expr_advance(state)
      negated <- TRUE
    }
    definition_expr_expect(state, "NULL")
    return(paste(left, "IS", if (negated) "NOT NULL" else "NULL"))
  }
  negated <- FALSE
  if (definition_expr_keyword(token, "NOT")) {
    definition_expr_advance(state)
    negated <- TRUE
    token <- definition_expr_peek(state)
  }
  if (definition_expr_keyword(token, "BETWEEN")) {
    definition_expr_advance(state)
    lower <- definition_expr_parse_additive(state)
    definition_expr_expect(state, "AND")
    upper <- definition_expr_parse_additive(state)
    return(paste(
      left,
      if (negated) "NOT BETWEEN" else "BETWEEN",
      lower,
      "AND",
      upper
    ))
  }
  if (definition_expr_keyword(token, "IN")) {
    definition_expr_advance(state)
    definition_expr_expect(state, "(")
    values <- list(definition_expr_parse_or(state))
    while (
      !is.null(definition_expr_peek(state)) &&
        identical(definition_expr_peek(state)$type, "comma")
    ) {
      definition_expr_advance(state)
      values[[length(values) + 1L]] <- definition_expr_parse_or(state)
    }
    definition_expr_expect(state, ")")
    return(paste0(
      left,
      if (negated) " NOT IN (" else " IN (",
      paste(unlist(values, use.names = FALSE), collapse = ", "),
      ")"
    ))
  }
  if (definition_expr_keyword(token, "LIKE")) {
    definition_expr_advance(state)
    pattern <- definition_expr_parse_additive(state)
    return(paste(left, if (negated) "NOT LIKE" else "LIKE", pattern))
  }
  if (definition_expr_keyword(token, "SIMILAR")) {
    definition_expr_advance(state)
    definition_expr_expect(state, "TO")
    pattern <- definition_expr_parse_additive(state)
    return(paste(
      left,
      if (negated) "NOT SIMILAR TO" else "SIMILAR TO",
      pattern
    ))
  }
  if (negated) {
    definition_expr_abort(
      "Expected `BETWEEN`, `IN`, `LIKE`, or `SIMILAR TO` after `NOT`."
    )
  }
  left
}

definition_expr_parse_additive <- function(state) {
  left <- definition_expr_parse_multiplicative(state)
  repeat {
    token <- definition_expr_peek(state)
    if (
      is.null(token) ||
        !identical(token$type, "operator") ||
        !(token$text %in% c("+", "-"))
    ) {
      return(left)
    }
    definition_expr_advance(state)
    left <- paste(left, token$text, definition_expr_parse_multiplicative(state))
  }
}

definition_expr_parse_multiplicative <- function(state) {
  left <- definition_expr_parse_primary(state)
  repeat {
    token <- definition_expr_peek(state)
    if (
      is.null(token) ||
        !identical(token$type, "operator") ||
        !(token$text %in% c("*", "/"))
    ) {
      return(left)
    }
    definition_expr_advance(state)
    left <- paste(left, token$text, definition_expr_parse_primary(state))
  }
}

definition_expr_parse_primary <- function(state) {
  token <- definition_expr_peek(state)
  if (is.null(token)) {
    definition_expr_abort("Unexpected end of definition expression.")
  }
  if (identical(token$type, "number")) {
    definition_expr_advance(state)
    return(token$text)
  }
  if (identical(token$type, "string")) {
    definition_expr_advance(state)
    return(token$text)
  }
  if (identical(token$type, "quoted_identifier")) {
    definition_expr_advance(state)
    name <- substr(token$text, 2L, nchar(token$text) - 1L)
    name <- gsub("``", "`", name, fixed = TRUE)
    return(definition_expr_parse_field_path(state, name))
  }
  if (identical(token$type, "operator") && identical(token$text, "(")) {
    definition_expr_advance(state)
    inner <- definition_expr_parse_or(state)
    definition_expr_expect(state, ")")
    return(paste0("(", inner, ")"))
  }
  if (identical(token$type, "operator") && identical(token$text, "-")) {
    definition_expr_advance(state)
    return(paste0("-", definition_expr_parse_primary(state)))
  }
  if (identical(token$type, "identifier")) {
    upper <- toupper(token$text)
    if (upper %in% c("TRUE", "FALSE")) {
      definition_expr_advance(state)
      return(upper)
    }
    if (identical(upper, "NULL")) {
      definition_expr_advance(state)
      return("NULL")
    }
    if (upper %in% c("INF", "NAN")) {
      definition_expr_advance(state)
      return(paste0(
        "CAST('",
        if (identical(upper, "INF")) "Infinity" else "NaN",
        "' AS DOUBLE)"
      ))
    }
    if (identical(upper, "CASE")) {
      definition_expr_advance(state)
      return(definition_expr_parse_case(state))
    }
    following <- if (state$position < length(state$tokens)) {
      state$tokens[[state$position + 1L]]
    }
    is_call <- !is.null(following) &&
      identical(following$type, "operator") &&
      identical(following$text, "(")
    if (is_call) {
      definition_expr_advance(state)
      definition_expr_advance(state)
      if (identical(upper, "COLUMNS")) {
        return(definition_expr_parse_columns(state))
      }
      if (identical(upper, "NOW")) {
        definition_expr_expect(state, ")")
        return("CURRENT_TIMESTAMP")
      }
      if (identical(upper, "INTERVAL")) {
        value <- definition_expr_parse_or(state)
        token <- definition_expr_peek(state)
        if (is.null(token) || !identical(token$type, "comma")) {
          definition_expr_abort("`INTERVAL()` requires a value and unit.")
        }
        definition_expr_advance(state)
        unit <- definition_expr_advance(state)
        if (
          is.null(unit) ||
            !identical(unit$type, "identifier") ||
            !tolower(unit$text) %in%
              c("seconds", "minutes", "hours", "days", "weeks")
        ) {
          definition_expr_abort(
            "Interval units must be seconds, minutes, hours, days, or weeks."
          )
        }
        definition_expr_expect(state, ")")
        return(paste0(
          "(",
          value,
          " * INTERVAL 1 ",
          toupper(sub("s$", "", unit$text)),
          ")"
        ))
      }
      if (!(upper %in% definition_expr_functions)) {
        state$issues <- rbind(
          state$issues,
          definition_expr_issue(
            "definition_expr_function",
            paste0(
              "Function `",
              token$text,
              "` is not in the definition whitelist (",
              paste(definition_expr_functions, collapse = ", "),
              ")."
            )
          )
        )
      }
      arguments <- definition_expr_parse_arguments(state)
      definition_expr_expect(state, ")")
      allowed <- definition_expr_arities[[upper]]
      if (!is.null(allowed) && !length(arguments) %in% allowed) {
        state$issues <- rbind(
          state$issues,
          definition_expr_issue(
            "definition_expr_function",
            paste0(
              "Function `",
              token$text,
              "` takes ",
              paste(allowed, collapse = " or "),
              " argument(s), not ",
              length(arguments),
              "."
            )
          )
        )
      }
      inner <- paste(arguments, collapse = ", ")
      if (identical(upper, "ROW_COUNT")) {
        return("COUNT(*)")
      }
      if (identical(upper, "COUNT_DISTINCT")) {
        return(paste0("COUNT(DISTINCT ", inner, ")"))
      }
      if (identical(upper, "ANY")) {
        return(paste0("BOOL_OR(", inner, ")"))
      }
      if (identical(upper, "ALL")) {
        return(paste0("BOOL_AND(", inner, ")"))
      }
      if (identical(upper, "IS_FINITE")) {
        return(paste0("ISFINITE(", inner, ")"))
      }
      if (identical(upper, "IS_INFINITE")) {
        return(paste0("ISINF(", inner, ")"))
      }
      if (identical(upper, "IS_NAN")) {
        return(paste0("ISNAN(", inner, ")"))
      }
      if (identical(upper, "MOD") && length(arguments) == 2L) {
        return(paste0(
          "MOD(MOD(",
          arguments[[1L]],
          ", ",
          arguments[[2L]],
          ") + ",
          arguments[[2L]],
          ", ",
          arguments[[2L]],
          ")"
        ))
      }
      return(paste0(upper, "(", inner, ")"))
    }
    definition_expr_advance(state)
    return(definition_expr_parse_field_path(state, token$text))
  }
  definition_expr_abort(paste0(
    "Unexpected `",
    token$text,
    "` in definition expression."
  ))
}

definition_expr_parse_columns <- function(state) {
  if (!is.null(state$selection)) {
    definition_expr_abort(
      "A definition may use at most one `COLUMNS()` selection."
    )
  }
  token <- definition_expr_peek(state)
  if (
    !is.null(token) &&
      identical(token$type, "operator") &&
      identical(token$text, "*")
  ) {
    definition_expr_advance(state)
    selected <- state$selection_columns
  } else if (
    !is.null(token) &&
      identical(token$type, "bracket") &&
      identical(token$text, "[")
  ) {
    definition_expr_advance(state)
    selected <- character()
    repeat {
      item <- definition_expr_advance(state)
      if (
        is.null(item) || !item$type %in% c("identifier", "quoted_identifier")
      ) {
        definition_expr_abort("`COLUMNS([...])` requires column names.")
      }
      name <- if (identical(item$type, "quoted_identifier")) {
        gsub(
          "``",
          "`",
          substr(item$text, 2L, nchar(item$text) - 1L),
          fixed = TRUE
        )
      } else {
        item$text
      }
      selected <- c(selected, name)
      next_token <- definition_expr_peek(state)
      if (
        !is.null(next_token) &&
          identical(next_token$type, "comma")
      ) {
        definition_expr_advance(state)
        next
      }
      if (
        is.null(next_token) ||
          !identical(next_token$type, "bracket") ||
          !identical(next_token$text, "]")
      ) {
        definition_expr_abort("`COLUMNS([...])` requires a closing `]`.")
      }
      definition_expr_advance(state)
      break
    }
    missing <- setdiff(selected, state$selection_columns)
    if (length(missing) > 0L) {
      definition_expr_abort(paste0(
        "Columns not found: ",
        paste(missing, collapse = ", "),
        "."
      ))
    }
  } else if (!is.null(token) && identical(token$type, "string")) {
    definition_expr_advance(state)
    pattern <- substr(token$text, 2L, nchar(token$text) - 1L)
    pattern <- gsub("''", "'", pattern, fixed = TRUE)
    unsupported <- grepl(
      "\\(\\?(?:[=!>]|<[=!])|\\\\[1-9]",
      pattern,
      perl = TRUE
    )
    valid <- tryCatch(
      {
        grepl(pattern, "", perl = TRUE)
        TRUE
      },
      warning = \(warning) FALSE,
      error = \(error) FALSE
    )
    if (unsupported || !valid) {
      definition_expr_abort(
        "`COLUMNS()` contains an invalid regular expression."
      )
    }
    selected <- state$selection_columns[vapply(
      state$selection_columns,
      \(column) grepl(pattern, column, perl = TRUE),
      logical(1)
    )]
  } else {
    definition_expr_abort(
      "`COLUMNS()` requires `*`, a column list, or a regular expression."
    )
  }
  definition_expr_expect(state, ")")
  if (length(selected) == 0L) {
    definition_expr_abort("`COLUMNS()` must select at least one column.")
  }
  state$selection <- selected
  definition_expr_selection_marker
}

definition_expr_parse_arguments <- function(state) {
  token <- definition_expr_peek(state)
  if (!is.null(token) && identical(token$text, ")")) {
    return(character())
  }
  arguments <- definition_expr_parse_or(state)
  while (
    !is.null(definition_expr_peek(state)) &&
      identical(definition_expr_peek(state)$type, "comma")
  ) {
    definition_expr_advance(state)
    arguments <- c(arguments, definition_expr_parse_or(state))
  }
  arguments
}

definition_expr_parse_field_path <- function(state, first) {
  path <- first
  while (
    !is.null(definition_expr_peek(state)) &&
      identical(definition_expr_peek(state)$type, "dot")
  ) {
    definition_expr_advance(state)
    token <- definition_expr_advance(state)
    if (
      is.null(token) ||
        !token$type %in% c("identifier", "quoted_identifier")
    ) {
      definition_expr_abort("Expected a field name after `.`.")
    }
    name <- if (identical(token$type, "quoted_identifier")) {
      gsub(
        "``",
        "`",
        substr(token$text, 2L, nchar(token$text) - 1L),
        fixed = TRUE
      )
    } else {
      token$text
    }
    path <- c(path, name)
  }
  reference <- paste(path, collapse = ".")
  if (!(reference %in% state$columns)) {
    state$issues <- rbind(
      state$issues,
      definition_expr_issue(
        "definition_expr_column",
        paste0(
          "Column or sibling definition `",
          reference,
          "` is not available on the target table."
        )
      )
    )
  }
  paste0(
    '"',
    paste(gsub('"', '""', path, fixed = TRUE), collapse = '"."'),
    '"'
  )
}

definition_expr_parse_case <- function(state) {
  branches <- character()
  while (definition_expr_keyword(definition_expr_peek(state), "WHEN")) {
    definition_expr_advance(state)
    condition <- definition_expr_parse_or(state)
    definition_expr_expect(state, "THEN")
    value <- definition_expr_parse_or(state)
    branches <- c(branches, paste("WHEN", condition, "THEN", value))
  }
  if (length(branches) == 0L) {
    definition_expr_abort("`CASE` requires at least one `WHEN ... THEN ...`.")
  }
  otherwise <- ""
  if (definition_expr_keyword(definition_expr_peek(state), "ELSE")) {
    definition_expr_advance(state)
    otherwise <- paste("ELSE", definition_expr_parse_or(state))
  }
  definition_expr_expect(state, "END")
  paste("CASE", paste(branches, collapse = " "), otherwise, "END")
}
