# Run from the package root:
# Rscript bench/ingest-baseline.R
# GRAFT_BENCH_LABEL=before Rscript bench/ingest-baseline.R before.csv

if (!requireNamespace("devtools", quietly = TRUE)) {
  stop("The benchmark requires the `devtools` package.")
}

devtools::load_all(".", quiet = TRUE)

benchmark_sizes <- c(100L, 1000L)
repetitions <- as.integer(Sys.getenv("GRAFT_BENCH_REPETITIONS", "1"))
if (length(repetitions) != 1L || is.na(repetitions) || repetitions < 1L) {
  stop("`GRAFT_BENCH_REPETITIONS` must be one positive integer.")
}

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) > 1L) {
  stop("Usage: Rscript bench/ingest-baseline.R [output.csv]")
}

git_output <- function(arguments) {
  tryCatch(
    system2("git", arguments, stdout = TRUE, stderr = FALSE),
    error = \(error) character()
  )
}

revision <- git_output(c("rev-parse", "--short", "HEAD"))
revision <- if (length(revision) == 1L) revision else NA_character_
dirty <- length(git_output(c("status", "--porcelain"))) > 0L
label <- Sys.getenv("GRAFT_BENCH_LABEL", revision)

manifest <- file.path("inst", "extdata", "personinfo.graft.json")
if (!file.exists(manifest)) {
  stop("Run this benchmark from the graft package root.")
}
schema <- kg_schema(manifest)
graft_version <- unname(
  read.dcf("DESCRIPTION", fields = "Version")[[1L]]
)

simple_person_records <- function(size) {
  list(
    Person = data.frame(
      id = sprintf("person:benchmark-%04d", seq_len(size)),
      full_name = sprintf("Benchmark person %04d", seq_len(size)),
      age = rep.int(42L, size),
      stringsAsFactors = FALSE
    )
  )
}

benchmark_ingest <- function(size, iteration) {
  store <- kg_connect_duckdb(schema, ":memory:", okf = "disabled")
  on.exit(kg_disconnect(store), add = TRUE)
  kg_init(store)

  records <- simple_person_records(size)
  provenance <- graft_provenance(
    producer = "ingest-benchmark",
    run_id = sprintf("records-%d-iteration-%d", size, iteration),
    idempotency_key = sprintf("records-%d-iteration-%d", size, iteration)
  )

  gc(verbose = FALSE)
  planning_elapsed <- system.time({
    plan <- graft_plan(store, records, provenance)
  })[["elapsed"]]
  commit_elapsed <- system.time({
    result <- graft_commit(store, plan)
  })[["elapsed"]]
  elapsed <- planning_elapsed + commit_elapsed

  stopifnot(
    identical(unname(result$inserted[["Person"]]), size),
    identical(unname(result$observed[["Person"]]), size),
    identical(unname(result$updated[["Person"]]), 0L),
    identical(unname(result$matched[["Person"]]), 0L)
  )

  data.frame(
    label = label,
    recorded_at_utc = format(
      Sys.time(),
      "%Y-%m-%dT%H:%M:%SZ",
      tz = "UTC"
    ),
    git_revision = revision,
    git_dirty = dirty,
    r_version = as.character(getRversion()),
    graft_version = graft_version,
    duckdb_version = as.character(utils::packageVersion("duckdb")),
    records = size,
    iteration = iteration,
    planning_seconds = unname(planning_elapsed),
    commit_seconds = unname(commit_elapsed),
    elapsed_seconds = unname(elapsed),
    inserted = unname(result$inserted[["Person"]]),
    updated = unname(result$updated[["Person"]]),
    matched = unname(result$matched[["Person"]]),
    observed = unname(result$observed[["Person"]]),
    stringsAsFactors = FALSE
  )
}

grid <- expand.grid(
  records = benchmark_sizes,
  iteration = seq_len(repetitions),
  KEEP.OUT.ATTRS = FALSE
)
results <- do.call(
  rbind,
  Map(benchmark_ingest, grid$records, grid$iteration)
)
rownames(results) <- NULL

print(results, row.names = FALSE)

if (length(arguments) == 1L) {
  output <- arguments[[1L]]
  output_directory <- dirname(output)
  if (!dir.exists(output_directory)) {
    dir.create(output_directory, recursive = TRUE)
  }
  utils::write.csv(results, output, row.names = FALSE, na = "")
  message("Wrote benchmark results to ", normalizePath(output))
}
