# EXPERIMENT ONLY. Explicit host composition through public package interfaces.
roundtrip_load <- function(checkout, envir) {
  for (file in c(
    "artifacts/content.R",
    "artifacts/backends.R",
    "artifacts/fixture.R",
    "vocabulary/publisher.R",
    "semantic-compatibility/model.R"
  )) {
    sys.source(file.path(checkout, "tools/experiments", file), envir)
  }
}

roundtrip_admit <- function(store, basis) {
  items <- artifact_read_basis(store, basis, "Commons synthesis")
  if (length(artifact_review(store, basis))) {
    artifact_error(
      "Input selection is stale; host review must rebuild context."
    )
  }
  items
}

roundtrip_generate <- function(store, basis, checkout) {
  # Check current policy before constructing a fresh agent. This is synthetic
  # host policy, not row-level authorization or erasure of earlier chat copies.
  items <- roundtrip_admit(store, basis)
  work <- tempfile("commons-artifact-roundtrip-")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE))
  options(commons.context_cache = FALSE)
  lookup <- function(id) {
    found <- Filter(function(item) item$ref$id == id, items)
    stopifnot(length(found) == 1L)
    found[[1L]]
  }
  fixture <- file.path(checkout, "tools/experiments/roundtrip/release")
  publication <- publish_bindings(file.path(fixture, "bindings.json"))
  release_refs <- lapply(
    c(
      "vocabulary.json",
      "bindings.json",
      "lab-a.yaml",
      "lab-b.yaml",
      "evidence.yaml"
    ),
    function(file) {
      artifact_save(
        store,
        paste0("artifact:", gsub("[.]", "-", file)),
        file.path(fixture, file),
        if (endsWith(file, ".yaml")) "application/yaml" else "application/json"
      )
    }
  )
  bundle_path <- file.path(work, "release.json")
  writeLines(artifact_json(publication), bundle_path)
  release <- artifact_save(
    store,
    "artifact:release",
    bundle_path,
    "application/json",
    release_refs,
    meaning = publication$references,
    producer = "vocabulary-publisher:fixture-v1"
  )
  context <- file.path(work, "vocabulary.md")
  writeLines(render_context(publication), context)
  report_context <- file.path(work, "report.md")
  original <- lookup("artifact:report")
  writeLines(
    c(
      paste("Artifact:", original$ref$id, "Revision:", original$ref$revision),
      rawToChar(original$bytes)
    ),
    report_context
  )
  data_path <- file.path(work, "evidence.parquet")
  writeBin(lookup("artifact:evidence")$bytes, data_path)
  dictionary_path <- file.path(work, "evidence.yaml")
  file.copy(
    file.path(fixture, "evidence.yaml"),
    dictionary_path
  )
  validation <- datadict::dd_validate_data(
    dictionary_path,
    html = file.path(work, "validation.html"),
    browse = FALSE
  )
  stopifnot(validation$status == 0L)
  dictionary <- artifact_save(
    store,
    "artifact:calculation-dictionary",
    dictionary_path,
    "application/yaml",
    meaning = publication$references
  )
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  data <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT * FROM read_parquet(",
      DBI::dbQuoteString(con, data_path),
      ")"
    )
  )
  mapped <- import_concept(
    publication,
    "artifact-workflow",
    list(evidence = data),
    "urn:example:sample"
  )
  stopifnot(
    identical(mapped$values, data$sample),
    identical(
      file_hash(dictionary_path),
      publication$references$dictionaries[[3L]]$sha256
    )
  )
  src <- commons::data_source(
    evidence = data,
    empty = data[FALSE, ],
    dictionary = dictionary_path
  )
  client <- ellmer::chat_openai_compatible(
    base_url = "https://fixture.invalid",
    model = "fixture",
    credentials = function() "offline",
    echo = "none"
  )
  agent <- commons::commons(
    client,
    data_sources = list(artifacts = src),
    context_layer = commons::context_layer(files = c(context, report_context))
  )
  requests <- list(
    list(
      name = "search_context",
      args = list(query = "Synthetic report Observed mean")
    ),
    list(
      name = "search_context",
      args = list(query = "Vocabulary release urn example sample")
    ),
    list(name = "call_metrics", args = list(metrics = list("total"))),
    list(
      name = "run_r",
      args = list(code = 'cat(jsonlite::toJSON(r1, dataframe = "rows"))')
    ),
    list(
      name = "run_r",
      args = list(code = 'plot(r1$total, main = "Retained synthetic total")')
    ),
    list(name = "run_sql", args = list(sql = "SELECT COUNT(*) AS n FROM empty"))
  )
  answer <- paste0(
    "# Commons synthesis\n\nSynthetic total: ",
    sum(data$value),
    ". No scientific inference is established.\n\n",
    "<commons-citation>\n> This fixture establishes no scientific claim.\n</commons-citation>"
  )
  results <- model_run(agent, requests, final_text = answer, async = TRUE)
  stopifnot(
    all(vapply(results, function(result) is.null(result$error), logical(1))),
    length(results) == 6L,
    identical(results[[3]]$extra$commons_tag, "A"),
    identical(results[[4]]$extra$commons_tag, "B"),
    identical(results[[5]]$extra$commons_tag, "B"),
    grepl(original$ref$revision, results[[1]]$value, fixed = TRUE),
    grepl(publication$vocabulary$release, results[[2]]$value, fixed = TRUE)
  )
  # Parse the deliberate JSON export from the real sandboxed R worker, not an
  # internal Commons result handle. This is version-pinned fixture protocol.
  calculated <- jsonlite::fromJSON(results[[4]]$value)
  stopifnot(
    identical(names(calculated), "total"),
    nrow(calculated) == 1L,
    calculated$total == sum(data$value)
  )
  images <- Filter(
    function(value) S7::S7_inherits(value, ellmer::ContentImageInline),
    results[[5]]$value
  )
  stopifnot(length(images) == 1L, identical(images[[1L]]@type, "image/png"))
  figure_path <- file.path(work, "commons-figure.png")
  writeBin(jsonlite::base64_dec(images[[1L]]@data), figure_path)
  stopifnot(identical(
    readBin(figure_path, "raw", 8L),
    as.raw(c(137, 80, 78, 71, 13, 10, 26, 10))
  ))
  stopifnot(grepl("[|][[:space:]]*0[|]", results[[6]]$value))
  table_path <- file.path(work, "commons-table.parquet")
  DBI::dbWriteTable(con, "calculated", calculated)
  DBI::dbExecute(
    con,
    paste0(
      "COPY calculated TO ",
      DBI::dbQuoteString(con, table_path),
      " (FORMAT PARQUET)"
    )
  )
  report_path <- file.path(work, "commons-report.md")
  writeLines(agent$last_turn()@text, report_path)
  # Preserve observed labels/SQL/model citation text separately from artifact
  # identity and dependency provenance. A matching quote is not factual proof.
  provenance_path <- file.path(work, "commons-provenance.json")
  evidence <- list(
    input_basis = basis,
    source_revisions = lapply(items, function(item) item$ref),
    vocabulary = publication$references,
    dictionary = dictionary,
    validation_status = validation$status,
    data_sha256 = artifact_hash(lookup("artifact:evidence")$bytes),
    requests = requests,
    answer = agent$last_turn()@text,
    results = lapply(results, function(result) {
      list(
        name = result$name,
        commons_tag = result$extra$commons_tag,
        text = if (is.character(result$value)) {
          result$value
        } else {
          "PNG preserved as a separate artifact"
        },
        markdown = result$extra$display$markdown
      )
    }),
    packages = lapply(c("commons", "ellmer", "datadict"), function(pkg) {
      list(package = pkg, version = as.character(utils::packageVersion(pkg)))
    })
  )
  writeLines(artifact_json(evidence), provenance_path)
  deps <- c(
    list(original$ref, release, dictionary),
    lapply(items, function(item) item$ref)
  )
  producer <- "commons:scripted-model-with-real-tools:v1"
  provenance <- artifact_save(
    store,
    "artifact:commons-provenance",
    provenance_path,
    "application/json",
    deps,
    publication$references,
    producer
  )
  table <- artifact_save(
    store,
    "artifact:commons-table",
    table_path,
    "application/vnd.apache.parquet",
    list(provenance),
    publication$references,
    producer
  )
  figure <- artifact_save(
    store,
    "artifact:commons-figure",
    figure_path,
    "image/png",
    list(provenance),
    publication$references,
    producer
  )
  report <- artifact_save(
    store,
    "artifact:commons-report",
    report_path,
    "text/markdown",
    list(table, figure, provenance),
    publication$references,
    producer
  )
  # No approve call here: returning generated output does not change eligibility.
  list(
    report = report,
    table = table,
    figure = figure,
    provenance = provenance,
    total = calculated$total,
    tag = results[[3]]$extra$commons_tag
  )
}

roundtrip_process <- function(checkout, root, backend, action) {
  roundtrip_load(checkout, environment())
  store <- artifact_store(
    root,
    backend,
    file.path(checkout, "tools/experiments/artifacts/artifact.data-dict.json")
  )
  on.exit(artifact_close(store))
  checkpoint_path <- file.path(root, "roundtrip-checkpoint.json")
  if (action %in% c("produce", "revise")) {
    old <- if (file.exists(checkpoint_path)) {
      artifact_read_json(checkpoint_path)
    } else {
      NULL
    }
    if (!is.null(old)) {
      old_basis <- artifact_read_json(artifact_digest_path(
        store$root,
        "selections",
        old$input_basis
      ))
      artifact_approve(store, old_basis$roots, "Commons synthesis")
    }
    inputs <- artifact_fixture(store, if (action == "produce") 1L else 2L)
    if (!is.null(old)) {
      # The old policy remains approved, but its dependencies changed.
      stale <- tryCatch(
        {
          roundtrip_admit(store, old$input_basis)
          FALSE
        },
        artifact_experiment_error = function(e) {
          grepl("stale", conditionMessage(e), fixed = TRUE)
        }
      )
      stopifnot(stale)
    }
    input_basis <- artifact_approve(
      store,
      list(inputs$report),
      "Commons synthesis"
    )
    generated <- roundtrip_generate(store, input_basis, checkout)
    stopifnot(identical(
      artifact_read_json(file.path(root, "policy.json"))$selection,
      input_basis
    ))
    checkpoint <- list(
      input_basis = input_basis,
      generated = generated,
      output_basis = artifact_approve(
        store,
        list(generated$report),
        "later artifact use"
      )
    )
    artifact_write(
      charToRaw(artifact_json(checkpoint)),
      checkpoint_path,
      replace = TRUE
    )
  }
  checkpoint <- artifact_read_json(checkpoint_path)
  values <- artifact_read_basis(
    store,
    checkpoint$output_basis,
    "later artifact use"
  )
  list(
    pid = Sys.getpid(),
    checkpoint = checkpoint,
    output_hashes = vapply(
      values,
      function(item) artifact_hash(item$bytes),
      character(1)
    ),
    report = rawToChar(values[[1L]]$bytes),
    total = checkpoint$generated$total
  )
}
