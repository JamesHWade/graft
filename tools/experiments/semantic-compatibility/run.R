# Run from the repository root; installation is separate from this offline run.
fixture_dir <- "tools/experiments/semantic-compatibility"
output <- Sys.getenv(
  "GRAFT_SEMANTIC_OUTPUT",
  tempfile("semantic-compatibility-", tmpdir = Sys.getenv("TMPDIR", "/tmp"))
)
dir.create(output, recursive = TRUE, showWarnings = FALSE)
output <- normalizePath(output)
checks <- character()
check <- function(ok, label) {
  if (!isTRUE(ok)) {
    stop(label, call. = FALSE)
  }
  checks <<- c(checks, label)
}
error_text <- function(expr) {
  tryCatch(
    {
      force(expr)
      NA_character_
    },
    error = conditionMessage
  )
}
export_spec <- function(path, command = "export-spec") {
  run <- datadict::dd_run(c(command, path))
  # dd_run deliberately interleaves stderr. A JSON document is one line.
  json <- run$output[grepl("^\\{", run$output)]
  stopifnot(length(json) == 1L)
  jsonlite::fromJSON(json, simplifyVector = FALSE)
}
sha <- function(path) digest::digest(file = path, algo = "sha256")

source(file.path(fixture_dir, "model.R"))

versions <- vapply(
  c(
    "commons",
    "ellmer",
    "shinychat",
    "datadict",
    "duckdb",
    "DBI",
    "httr2",
    "jsonlite",
    "yaml",
    "digest"
  ),
  function(pkg) {
    as.character(utils::packageVersion(pkg))
  },
  character(1)
)
check(
  utils::packageVersion("commons") >= "0.1.0.9000",
  "Current Commons installed"
)
check(utils::packageVersion("ellmer") >= "0.5.0", "Compatible ellmer installed")
con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
sales <- data.frame(
  id = 1:4,
  revenue = c(10, 20, NA, 5),
  region = c("EMEA", "APAC", "EMEA", "EMEA")
)
DBI::dbWriteTable(con, "sales", sales)
parquet <- file.path(output, "sales.parquet")
DBI::dbExecute(
  con,
  paste0(
    "COPY sales TO ",
    DBI::dbQuoteString(con, parquet),
    " (FORMAT PARQUET, COMPRESSION UNCOMPRESSED, OVERWRITE_OR_IGNORE TRUE)"
  )
)
file.copy(file.path(fixture_dir, "data-dict.yaml"), output, overwrite = TRUE)
path <- file.path(output, "data-dict.yaml")
input_sha <- sha(parquet)
datadict::dd_run(c("validate-spec", path))
valid <- datadict::dd_validate_data(
  path,
  html = file.path(output, "valid.html"),
  browse = FALSE
)
check(file.exists(valid$html), "Valid data report is preserved")
check(valid$status == 0L, "Valid Parquet data passes value validation")
export <- export_spec(path)
profile <- export_spec(path, "export-data")
jsonlite::write_json(
  export,
  file.path(output, "export.json"),
  pretty = TRUE,
  auto_unbox = TRUE
)
check(
  length(export$tables[[1]]$definitions) == 5L,
  "Five typed definitions exported"
)
defs <- setNames(
  export$tables[[1]]$definitions,
  vapply(export$tables[[1]]$definitions, `[[`, "", "name")
)
check(
  defs$emea$kind == "filter" && defs$emea$type == "boolean",
  "Filter kind and type"
)
check(
  defs$total$kind == "metric" && defs$doubled$kind == "derived",
  "Aggregate versus row grain"
)
check(
  identical(unlist(defs$total_doubled$definitions), "doubled"),
  "Direct definition dependency exported"
)
check(
  any(vapply(
    defs$total$translations,
    function(x) x$target == "SQL(duckdb)",
    logical(1)
  )),
  "DuckDB translation exported"
)

# Both engines consume these same preserved bytes. Commons gets detached frames
# read from the validated file, not a independently regenerated data frame.
detached <- DBI::dbGetQuery(
  con,
  paste0("SELECT * FROM read_parquet(", DBI::dbQuoteString(con, parquet), ")")
)
src <- commons::data_source(sales = detached, dictionary = path)
client <- ellmer::chat_openai_compatible(
  base_url = "https://fixture.invalid",
  model = "fixture",
  credentials = function() "offline",
  echo = "none"
)
agent <- commons::commons(client, data_sources = list(warehouse = src))
results <- model_run(
  agent,
  list(
    list(name = "call_metrics", args = list(metrics = list("total"))),
    list(
      name = "call_metrics",
      args = list(metrics = list("total"), filters = list("emea"))
    ),
    list(name = "call_metrics", args = list(metrics = list("total_doubled"))),
    list(name = "call_metrics", args = list(metrics = list("constant"))),
    list(
      name = "run_sql",
      args = list(
        sql = "SELECT id, {{doubled}} AS doubled FROM sales ORDER BY id"
      )
    )
  )
)
check(length(results) == 5L, "Real Commons dispatched all five model requests")
for (i in seq_along(results)) {
  check(is.null(results[[i]]$error), paste("Calculation", i, "succeeded"))
}
check(
  grepl("|    35|", results[[1]]$value, fixed = TRUE),
  "SUM ignores the nullable row and returns 35"
)
check(
  grepl("|    15|", results[[2]]$value, fixed = TRUE),
  "Governed filter returns 15"
)
check(
  grepl("|            70|", results[[3]]$value, fixed = TRUE),
  "Derived aggregate returns 70"
)
check(
  grepl("|       42|", results[[4]]$value, fixed = TRUE),
  "Constant metric returns 42"
)
check(
  grepl("1 NAs", results[[5]]$value, fixed = TRUE),
  "Derived row preserves missing value"
)
check(
  all(vapply(
    results[1:4],
    function(x) identical(x$extra$commons_tag, "A"),
    logical(1)
  )),
  "Governed calculations emit Commons A provenance"
)
check(
  grepl("SQL(duckdb)", results[[1]]$value, fixed = TRUE),
  "Calculation names its translation target"
)
check(
  grepl(
    "WHERE (\"region\" = 'EMEA')",
    results[[2]]$extra$display$markdown,
    fixed = TRUE
  ),
  "Filtered calculation records executed predicate"
)
check(
  grepl("128 bits", results[[1]]$value, fixed = TRUE),
  "Calculation preserves overflow translation caveat"
)
# Run the upstream exported bare SQL directly, without introducing an evaluator.
for (name in c("total", "doubled", "constant")) {
  translation <- Filter(
    function(x) identical(x$target, "SQL(duckdb)"),
    defs[[name]]$translations
  )[[1]]
  value <- DBI::dbGetQuery(
    con,
    paste("SELECT", translation$code, "AS value FROM sales")
  )$value
  expected <- switch(
    name,
    total = 35,
    doubled = c(20, 40, NA, 10),
    constant = rep(42, 4)
  )
  check(
    isTRUE(all.equal(as.numeric(value), expected)),
    paste("Upstream SQL translation executes:", name)
  )
}
# Constant bare SQL is scalar per row; Commons deliberately emits one metric row.
# This orchestration must remain explicit even with a canonical compiler.
check(
  all(vapply(
    c("|  1|      20|", "|  2|      40|", "|  3|      NA|", "|  4|      10|"),
    function(row) grepl(row, results[[5]]$value, fixed = TRUE),
    logical(1)
  )),
  "Derived row result matches all four expected cells"
)
saveRDS(results, file.path(output, "commons-results.rds"))
writeLines(
  capture.output(str(results, max.level = 7)),
  file.path(output, "commons-results.txt")
)
check(
  identical(input_sha, sha(parquet)),
  "Validated data bytes unchanged after calculation"
)

# A dictionary constructor is not value validation. Invalid enum and negative
# value must fail the data validator even though profiling still succeeds.
invalid_dir <- file.path(output, "invalid-values")
dir.create(invalid_dir, showWarnings = FALSE)
file.copy(path, invalid_dir, overwrite = TRUE)
DBI::dbExecute(
  con,
  "UPDATE sales SET revenue = -1, region = 'UNKNOWN' WHERE id = 1"
)
DBI::dbExecute(
  con,
  paste0(
    "COPY sales TO ",
    DBI::dbQuoteString(con, file.path(invalid_dir, "sales.parquet")),
    " (FORMAT PARQUET, COMPRESSION UNCOMPRESSED, OVERWRITE_OR_IGNORE TRUE)"
  )
)
invalid_path <- file.path(invalid_dir, "data-dict.yaml")
invalid <- datadict::dd_validate_data(
  invalid_path,
  html = file.path(output, "invalid.html"),
  browse = FALSE
)
check(
  invalid$status != 0L && file.exists(invalid$html),
  "Invalid values return nonzero validation report status"
)
check(
  length(export_spec(invalid_path, "export-data")$tables) == 1L,
  "Profiling succeeds despite invalid values"
)
check(
  inherits(
    commons::data_source(
      sales = DBI::dbReadTable(con, "sales"),
      dictionary = invalid_path
    ),
    "commons_data_source"
  ),
  "Commons construction does not enforce data-value constraints"
)

cases <- list(
  invalid_definition = "missing_column + 1",
  related_reference = "other.revenue + 1",
  mixed_grain = "SUM(revenue) + revenue",
  r_language = "!is.na(revenue)"
)
case_results <- list()
for (name in names(cases)) {
  dict <- yaml::read_yaml(path)
  dict$tables[[1]]$columns[[1]]$constraints <- list("primary_key")
  dict$tables[[1]]$columns[[3]]$values <- as.list(
    dict$tables[[1]]$columns[[3]]$values
  )
  dict$tables[[1]]$definitions <- list(list(
    name = "probe",
    expr = cases[[name]]
  ))
  if (name == "mixed_grain") {
    dict$tables[[1]]$definitions[[2]] <- list(
      name = "total",
      expr = "SUM(revenue)"
    )
  }
  if (name == "related_reference") {
    dict$tables[[2]] <- list(
      name = "other",
      columns = list(list(
        name = "revenue",
        type = "number(quantity)",
        range = list(0, 100)
      ))
    )
  }
  if (name == "r_language") {
    dict$tables[[1]]$definitions[[1]]$language <- "r"
  }
  probe <- file.path(output, paste0(name, ".yaml"))
  yaml::write_yaml(dict, probe)
  dd_error <- error_text(datadict::dd_run(c("validate-spec", probe)))
  commons_error <- error_text(
    if (name == "related_reference") {
      commons::data_source(
        sales = detached,
        other = detached["revenue"],
        dictionary = probe
      )
    } else {
      commons::data_source(sales = detached, dictionary = probe)
    }
  )
  case_results[[name]] <- list(
    data_dict_error = dd_error,
    commons_error = commons_error
  )
  if (name %in% c("invalid_definition", "related_reference")) {
    check(
      !is.na(dd_error) &&
        !is.na(commons_error) &&
        grepl("not found|Unknown|unknown", dd_error),
      paste(name, "rejected for unresolved reference by both constructors")
    )
  }
  if (name == "r_language") {
    check(
      is.na(dd_error) && !is.na(commons_error),
      "R-language definition exposes compiler divergence"
    )
  }
  if (name == "mixed_grain") {
    check(
      is.na(dd_error) && is.na(commons_error),
      "Mixed-grain definition validates in both constructors"
    )
    mixed_agent <- commons::commons(
      client,
      data_sources = commons::data_source(sales = detached, dictionary = probe)
    )
    refusal <- suppressWarnings(model_run(
      mixed_agent,
      list(list(
        name = "call_metrics",
        args = list(metrics = list("total"), dimensions = list("probe"))
      ))
    ))[[1]]
    case_results[[name]]$invocation_error <- conditionMessage(refusal$error)
    check(
      grepl("mix|grain", case_results[[name]]$invocation_error),
      "Mixed grain refused at Commons invocation"
    )
  }
}
DBI::dbDisconnect(con, shutdown = TRUE)
summary <- list(
  versions = versions,
  cli = datadict::dd_run("--version")$output,
  validated_data_sha256 = input_sha,
  dictionary_sha256 = sha(path),
  checks = checks,
  cases = case_results,
  definition_metadata = defs,
  output_directory = output
)
jsonlite::write_json(
  summary,
  file.path(output, "results.json"),
  pretty = TRUE,
  auto_unbox = TRUE,
  na = "null"
)
cat(
  length(checks),
  "checks passed. Evidence:",
  file.path(output, "results.json"),
  "\n"
)
