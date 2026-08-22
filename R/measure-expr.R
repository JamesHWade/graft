measure_expr_aggregates <- c("SUM", "COUNT", "AVG", "MIN", "MAX")

measure_expr_no_issues <- function() {
  data.frame(
    rule = character(),
    message = character(),
    stringsAsFactors = FALSE
  )
}

measure_expr_issue <- function(rule, message) {
  data.frame(rule = rule, message = message, stringsAsFactors = FALSE)
}

measure_expr_check <- function(expr, columns) {
  tokens <- tryCatch(
    measure_expr_tokenize(expr),
    graft_measure_expr_error = \(condition) condition
  )
  if (rlang::is_condition(tokens)) {
    return(list(
      issues = measure_expr_issue(
        "measure_expr_parse",
        conditionMessage(tokens)
      ),
      sql = NA_character_
    ))
  }
  state <- new.env(parent = emptyenv())
  state$tokens <- tokens
  state$position <- 1L
  state$issues <- measure_expr_no_issues()
  state$columns <- columns
  sql <- tryCatch(
    {
      out <- measure_expr_parse_or(state)
      remaining <- measure_expr_peek(state)
      if (!is.null(remaining)) {
        measure_expr_abort(paste0(
          "Unexpected `",
          remaining$text,
          "` after end of expression."
        ))
      }
      out
    },
    graft_measure_expr_error = \(condition) {
      state$issues <- rbind(
        state$issues,
        measure_expr_issue("measure_expr_parse", conditionMessage(condition))
      )
      NA_character_
    }
  )
  if (nrow(state$issues) > 0L) {
    sql <- NA_character_
  }
  list(issues = state$issues, sql = sql)
}

measure_expr_abort <- function(message) {
  rlang::abort(message, class = "graft_measure_expr_error")
}

measure_expr_tokenize <- function(expr) {
  if (!is_nonempty_string(expr)) {
    measure_expr_abort("A measure expression must be one non-empty string.")
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
      c("number", "^[0-9]+(\\.[0-9]+)?"),
      c("string", "^'([^']|'')*'"),
      c("identifier", "^[A-Za-z_][A-Za-z0-9_]*"),
      c("operator", "^(!=|<=|>=|[=<>+*/()-])"),
      c("comma", "^,")
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
      measure_expr_abort(paste0(
        "Unexpected character `",
        substr(source, 1L, 1L),
        "` in measure expression."
      ))
    }
  }
  if (length(tokens) == 0L) {
    measure_expr_abort("A measure expression must be one non-empty string.")
  }
  tokens
}

measure_expr_peek <- function(state) {
  if (state$position > length(state$tokens)) {
    return(NULL)
  }
  state$tokens[[state$position]]
}

measure_expr_advance <- function(state) {
  token <- measure_expr_peek(state)
  state$position <- state$position + 1L
  token
}

measure_expr_expect <- function(state, text) {
  token <- measure_expr_peek(state)
  if (is.null(token) || !identical(toupper(token$text), toupper(text))) {
    observed <- if (is.null(token)) {
      "end of expression"
    } else {
      paste0("`", token$text, "`")
    }
    measure_expr_abort(paste0(
      "Expected `",
      text,
      "` but found ",
      observed,
      "."
    ))
  }
  measure_expr_advance(state)
}

measure_expr_keyword <- function(token, keyword) {
  !is.null(token) &&
    identical(token$type, "identifier") &&
    identical(toupper(token$text), keyword)
}

measure_expr_parse_or <- function(state) {
  left <- measure_expr_parse_and(state)
  while (measure_expr_keyword(measure_expr_peek(state), "OR")) {
    measure_expr_advance(state)
    left <- paste(left, "OR", measure_expr_parse_and(state))
  }
  left
}

measure_expr_parse_and <- function(state) {
  left <- measure_expr_parse_not(state)
  while (measure_expr_keyword(measure_expr_peek(state), "AND")) {
    measure_expr_advance(state)
    left <- paste(left, "AND", measure_expr_parse_not(state))
  }
  left
}

measure_expr_parse_not <- function(state) {
  if (measure_expr_keyword(measure_expr_peek(state), "NOT")) {
    measure_expr_advance(state)
    return(paste("NOT", measure_expr_parse_not(state)))
  }
  measure_expr_parse_comparison(state)
}

measure_expr_parse_comparison <- function(state) {
  left <- measure_expr_parse_additive(state)
  token <- measure_expr_peek(state)
  if (
    !is.null(token) &&
      identical(token$type, "operator") &&
      token$text %in% c("=", "!=", "<", "<=", ">", ">=")
  ) {
    measure_expr_advance(state)
    left <- paste(left, token$text, measure_expr_parse_additive(state))
  }
  left
}

measure_expr_parse_additive <- function(state) {
  left <- measure_expr_parse_multiplicative(state)
  repeat {
    token <- measure_expr_peek(state)
    if (
      is.null(token) ||
        !identical(token$type, "operator") ||
        !(token$text %in% c("+", "-"))
    ) {
      return(left)
    }
    measure_expr_advance(state)
    left <- paste(left, token$text, measure_expr_parse_multiplicative(state))
  }
}

measure_expr_parse_multiplicative <- function(state) {
  left <- measure_expr_parse_primary(state)
  repeat {
    token <- measure_expr_peek(state)
    if (
      is.null(token) ||
        !identical(token$type, "operator") ||
        !(token$text %in% c("*", "/"))
    ) {
      return(left)
    }
    measure_expr_advance(state)
    left <- paste(left, token$text, measure_expr_parse_primary(state))
  }
}

measure_expr_parse_primary <- function(state) {
  token <- measure_expr_peek(state)
  if (is.null(token)) {
    measure_expr_abort("Unexpected end of measure expression.")
  }
  if (identical(token$type, "number")) {
    measure_expr_advance(state)
    return(token$text)
  }
  if (identical(token$type, "string")) {
    measure_expr_advance(state)
    return(token$text)
  }
  if (identical(token$type, "operator") && identical(token$text, "(")) {
    measure_expr_advance(state)
    inner <- measure_expr_parse_or(state)
    measure_expr_expect(state, ")")
    return(paste0("(", inner, ")"))
  }
  if (identical(token$type, "operator") && identical(token$text, "-")) {
    measure_expr_advance(state)
    return(paste0("-", measure_expr_parse_primary(state)))
  }
  if (identical(token$type, "identifier")) {
    upper <- toupper(token$text)
    if (upper %in% c("TRUE", "FALSE")) {
      measure_expr_advance(state)
      return(upper)
    }
    following <- if (state$position < length(state$tokens)) {
      state$tokens[[state$position + 1L]]
    }
    is_call <- !is.null(following) &&
      identical(following$type, "operator") &&
      identical(following$text, "(")
    if (is_call) {
      measure_expr_advance(state)
      measure_expr_advance(state)
      if (!(upper %in% measure_expr_aggregates)) {
        state$issues <- rbind(
          state$issues,
          measure_expr_issue(
            "measure_expr_function",
            paste0(
              "Function `",
              token$text,
              "` is not in the measure whitelist (",
              paste(measure_expr_aggregates, collapse = ", "),
              ")."
            )
          )
        )
      }
      inner <- measure_expr_parse_aggregate_body(state, upper)
      measure_expr_expect(state, ")")
      return(paste0(upper, "(", inner, ")"))
    }
    measure_expr_advance(state)
    if (!(token$text %in% state$columns)) {
      state$issues <- rbind(
        state$issues,
        measure_expr_issue(
          "measure_expr_column",
          paste0(
            "Column `",
            token$text,
            "` is not a field of the target class."
          )
        )
      )
    }
    return(paste0('"', token$text, '"'))
  }
  measure_expr_abort(paste0(
    "Unexpected `",
    token$text,
    "` in measure expression."
  ))
}

measure_expr_parse_aggregate_body <- function(state, fn) {
  token <- measure_expr_peek(state)
  if (
    identical(fn, "COUNT") &&
      !is.null(token) &&
      identical(token$type, "operator") &&
      identical(token$text, "*")
  ) {
    measure_expr_advance(state)
    return("*")
  }
  if (measure_expr_keyword(token, "DISTINCT")) {
    measure_expr_advance(state)
    if (!identical(fn, "COUNT")) {
      state$issues <- rbind(
        state$issues,
        measure_expr_issue(
          "measure_expr_distinct",
          "`DISTINCT` is only supported inside `COUNT()`."
        )
      )
    }
    return(paste("DISTINCT", measure_expr_parse_or(state)))
  }
  measure_expr_parse_or(state)
}
