# Synthetic producer shared by both metadata compositions.
artifact_fixture <- function(store, version = 1L) {
  work <- tempfile("artifact-producer-")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE))
  data <- data.frame(sample = c("s1", "s2", "s3"), value = c(1, 2, 2 + version))
  source <- file.path(work, "source.json")
  writeLines(artifact_json(data), source)
  source_ref <- artifact_save(
    store,
    "artifact:source",
    source,
    "application/json"
  )
  meaning <- file.path(work, "meaning.json")
  writeLines(
    artifact_json(list(
      dictionary = "synthetic:v1",
      fields = c("sample", "value"),
      definition = "mean(value)",
      vocabulary = "measurement:v1",
      binding = "value-is-synthetic-measurement:v1",
      units = "arbitrary"
    )),
    meaning
  )
  meaning_ref <- artifact_save(
    store,
    "artifact:meaning",
    meaning,
    "application/json"
  )
  meaning_pin <- list(release = meaning_ref$revision)
  table <- file.path(work, "evidence.parquet")
  conn <- DBI::dbConnect(duckdb::duckdb())
  tryCatch(
    {
      DBI::dbWriteTable(conn, "evidence", data)
      DBI::dbExecute(
        conn,
        paste0(
          "COPY evidence TO ",
          DBI::dbQuoteString(conn, table),
          " (FORMAT PARQUET)"
        )
      )
    },
    finally = DBI::dbDisconnect(conn, shutdown = TRUE)
  )
  table_ref <- artifact_save(
    store,
    "artifact:evidence",
    table,
    "application/vnd.apache.parquet",
    list(source_ref, meaning_ref),
    meaning_pin
  )
  figure <- file.path(work, "figure.png")
  grDevices::png(figure, width = 320, height = 240)
  tryCatch(
    graphics::plot(data$value, type = "b", main = "Synthetic measurements"),
    finally = grDevices::dev.off()
  )
  figure_ref <- artifact_save(
    store,
    "artifact:figure",
    figure,
    "image/png",
    list(table_ref, meaning_ref),
    meaning_pin
  )
  report <- file.path(work, "report.md")
  writeLines(
    c(
      "# Synthetic report",
      "",
      paste("Observed mean:", mean(data$value)),
      paste("Interpretation revision:", version),
      "This fixture establishes no scientific claim."
    ),
    report
  )
  report_ref <- artifact_save(
    store,
    "artifact:report",
    report,
    "text/markdown",
    list(table_ref, figure_ref, meaning_ref),
    meaning_pin
  )
  draft <- file.path(work, "draft.md")
  writeLines("Unapproved speculation: never automatically reusable.", draft)
  draft_ref <- artifact_save(store, "artifact:draft", draft, "text/markdown")
  list(
    report = report_ref,
    evidence = table_ref,
    figure = figure_ref,
    draft = draft_ref
  )
}

artifact_process <- function(checkout, root, backend, action) {
  path <- file.path(checkout, "tools/experiments/artifacts")
  env <- new.env(parent = globalenv())
  for (file in c("content.R", "backends.R", "fixture.R")) {
    sys.source(file.path(path, file), env)
  }
  store <- env$artifact_store(
    root,
    backend,
    file.path(path, "artifact.data-dict.json")
  )
  on.exit(env$artifact_close(store))
  if (action == "produce") {
    refs <- env$artifact_fixture(store)
    basis <- env$artifact_approve(store, list(refs$report), "later synthesis")
    env$artifact_write(
      charToRaw(env$artifact_json(list(basis = basis, refs = refs))),
      file.path(root, "checkpoint.json")
    )
  }
  checkpoint <- env$artifact_read_json(file.path(root, "checkpoint.json"))
  if (action == "revise") {
    env$artifact_fixture(store, 2L)
  }
  items <- env$artifact_read_basis(store, checkpoint$basis, "later synthesis")
  list(
    pid = Sys.getpid(),
    basis = checkpoint$basis,
    selection = lapply(items, function(item) item$ref),
    hashes = vapply(
      items,
      function(item) env$artifact_hash(item$bytes),
      character(1)
    ),
    report = rawToChar(items[[1L]]$bytes),
    changed = env$artifact_review(store, checkpoint$basis),
    index = env$artifact_index(store)
  )
}
