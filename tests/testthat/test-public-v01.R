test_that("v0.1 public API exposes exactly 20 functions", {
  expected <- c(
    "graft_at",
    "graft_close",
    "graft_commit",
    "graft_find",
    "graft_get",
    "graft_history",
    "graft_ingest",
    "graft_measure",
    "graft_measures",
    "graft_open",
    "graft_plan",
    "graft_provenance",
    "graft_query",
    "graft_review",
    "graft_schema",
    "graft_snapshot",
    "graft_status",
    "graft_sync",
    "graft_tools",
    "graft_view_snapshot"
  )

  expect_identical(sort(getNamespaceExports("graft")), expected)
})

test_that("v0.1 public API completes the governed knowledge loop", {
  directory <- withr::local_tempdir()
  manifest <- file.path(directory, "tempest.graft.json")
  schema <- graft_schema(tempest_schema_path(), output = manifest)
  store_path <- file.path(directory, "knowledge.duckdb")
  store <- graft_open(schema, store_path)
  withr::defer(if (!store@closed) graft_close(store))
  record_id <- "graft:00000000000000000000000000"
  second_id <- "graft:00000000000000000000000001"
  records <- list(
    Entity = data.frame(
      id = record_id,
      preferred_name = "Polyethylene",
      inchikey = "XLYOFNOQVPJJNP-UHFFFAOYSA-N"
    )
  )
  provenance <- graft_provenance(
    "public-workflow",
    idempotency_key = "public-insert"
  )

  plan <- graft_plan(store, records, provenance)
  committed <- graft_commit(store, plan)
  current <- graft_get(store, record_id, include = character())
  found <- graft_find(store, "polyethylene")
  lookup <- graft_query(
    store,
    "lookup",
    list(
      namespace = "inchikey",
      value = "XLYOFNOQVPJJNP-UHFFFAOYSA-N"
    )
  )
  history <- graft_history(store, record_id)

  expect_identical(plan@valid, TRUE)
  expect_type(committed, "list")
  expect_identical(is.object(committed), FALSE)
  expect_identical(current$record$preferred_name, "Polyethylene")
  expect_identical(found$id, record_id)
  expect_identical(lookup$record_id, record_id)
  expect_equal(nrow(history), 1L)

  bundle <- graft_sync(store)
  status <- graft_status(store)
  expect_type(bundle, "list")
  expect_identical(is.object(bundle), FALSE)
  expect_type(status, "list")
  expect_identical(is.object(status), FALSE)
  expect_identical(status$status, "current")

  concept_files <- list.files(
    bundle$path,
    pattern = "[.]md$",
    recursive = TRUE,
    full.names = TRUE
  )
  concept <- concept_files[vapply(
    concept_files,
    \(path) {
      any(grepl(
        record_id,
        readLines(path, warn = FALSE, encoding = "UTF-8"),
        fixed = TRUE
      ))
    },
    logical(1)
  )]
  expect_length(concept, 1L)
  lines <- readLines(concept, warn = FALSE, encoding = "UTF-8")
  line <- grep("preferred_name: Polyethylene", lines, fixed = TRUE)
  expect_length(line, 1L)
  lines[[line]] <- sub(
    "preferred_name: Polyethylene",
    "preferred_name: Polyethylene resin",
    lines[[line]],
    fixed = TRUE
  )
  writeLines(lines, concept, useBytes = TRUE)

  review <- graft_review(
    store,
    provenance = graft_provenance(
      "public-review",
      idempotency_key = "public-review"
    )
  )
  reviewed <- graft_commit(store, review)
  graft_sync(store)
  expect_identical(review@source, "okf")
  expect_identical(review@valid, TRUE)
  expect_type(reviewed, "list")
  expect_identical(is.object(reviewed), FALSE)
  expect_identical(
    graft_get(store, record_id, include = character())$record$preferred_name,
    "Polyethylene resin"
  )

  graft_ingest(
    store,
    list(
      Entity = data.frame(
        id = second_id,
        preferred_name = "Polypropylene"
      )
    ),
    graft_provenance(
      "public-workflow",
      idempotency_key = "public-convenience"
    )
  )
  tools <- graft_tools(store)
  tool_results <- list(
    tools$graft_find(query = "resin"),
    tools$graft_get(id = record_id, include = character()),
    tools$graft_query(
      operation = "identifiers",
      request = list(id = record_id)
    ),
    tools$graft_history(id = record_id)
  )
  expect_named(
    tools,
    c("graft_find", "graft_get", "graft_query", "graft_history")
  )
  expect_identical(
    vapply(tools, inherits, logical(1), "ellmer::ToolDef"),
    stats::setNames(rep(TRUE, 4L), names(tools))
  )
  expect_identical(
    vapply(
      tools,
      \(tool) agent_tool_prop(tool, "annotations")$read_only_hint,
      logical(1)
    ),
    stats::setNames(rep(TRUE, 4L), names(tools))
  )
  exposed <- unique(unlist(lapply(tools, function(tool) {
    arguments <- agent_tool_prop(tool, "arguments")
    names(agent_tool_prop(arguments, "properties"))
  })))
  expect_identical(
    intersect(
      exposed,
      c("sql", "path", "url", "network", "connection", "write")
    ),
    character()
  )
  for (tool_result in tool_results) {
    expect_named(tool_result, c("result", "truncated", "limit", "receipt"))
    expect_named(tool_result$receipt, c("store", "boundary", "schema"))
  }

  graft_close(store)
  loaded <- graft_schema(manifest)
  read_only <- graft_open(
    loaded,
    store_path,
    read_only = TRUE
  )
  withr::defer(graft_close(read_only))
  expect_identical(
    graft_get(
      read_only,
      record_id,
      include = character()
    )$record$preferred_name,
    "Polyethylene resin"
  )
  expect_gt(nrow(graft_history(read_only, record_id)), 0L)
  expect_identical(graft_status(read_only)$status, "stale")
  condition <- rlang::catch_cnd(graft_ingest(
    read_only,
    records,
    graft_provenance("read-only")
  ))
  expect_s3_class(condition, "graft_backend_error")
})

test_that("graft_schema validates source and output boundaries", {
  local_mocked_bindings(
    compile_schema_manifest = function(schema, output) {
      file.copy(tempest_manifest_path(), output)
      load_schema_manifest(output)
    }
  )
  temporary <- graft_schema(tempest_schema_path())
  expect_identical(file.exists(temporary@path), TRUE)
  expect_match(temporary@path, "[.]graft[.]json$")

  unknown <- withr::local_tempfile(fileext = ".txt")
  writeLines("not a schema", unknown)
  unknown_error <- rlang::catch_cnd(graft_schema(unknown))
  output_error <- rlang::catch_cnd(graft_schema(
    tempest_schema_path(),
    output = withr::local_tempfile(fileext = ".json")
  ))
  manifest_output_error <- rlang::catch_cnd(graft_schema(
    tempest_manifest_path(),
    output = withr::local_tempfile(fileext = ".graft.json")
  ))

  expect_s3_class(unknown_error, "graft_schema_error")
  expect_s3_class(output_error, "graft_schema_error")
  expect_s3_class(manifest_output_error, "graft_schema_error")
})

test_that("graft_tools requires a GraftStore or GraftView", {
  schema <- graft_schema(tempest_manifest_path())
  store <- graft_open(schema)
  withr::defer(graft_close(store))

  legacy <- as_graft_store_internal(store)
  condition <- rlang::catch_cnd(graft_tools(legacy))

  expect_s3_class(condition, "graft_backend_error")
  expect_match(conditionMessage(condition), "GraftStore")
})

test_that("OKF review rejects post-review bundle and store changes", {
  schema <- graft_schema(tempest_manifest_path())
  directory <- withr::local_tempdir()
  store <- graft_open(
    schema,
    file.path(directory, "review.duckdb")
  )
  withr::defer(graft_close(store))
  record_id <- "graft:00000000000000000000000002"
  graft_ingest(
    store,
    list(
      Entity = data.frame(
        id = record_id,
        preferred_name = "Review base"
      )
    ),
    graft_provenance("review-setup", idempotency_key = "review-setup")
  )
  bundle <- graft_sync(store)
  concept_files <- list.files(
    bundle$path,
    pattern = "[.]md$",
    recursive = TRUE,
    full.names = TRUE
  )
  concept <- concept_files[vapply(
    concept_files,
    \(path) {
      any(grepl(
        record_id,
        readLines(path, warn = FALSE, encoding = "UTF-8"),
        fixed = TRUE
      ))
    },
    logical(1)
  )]
  edit_concept <- function(from, to) {
    lines <- readLines(concept, warn = FALSE, encoding = "UTF-8")
    line <- grep(from, lines, fixed = TRUE)
    stopifnot(length(line) == 1L)
    lines[[line]] <- sub(from, to, lines[[line]], fixed = TRUE)
    writeLines(lines, concept, useBytes = TRUE)
  }

  edit_concept("preferred_name: Review base", "preferred_name: Reviewed")
  review <- graft_review(
    store,
    provenance = graft_provenance(
      "reviewer",
      idempotency_key = "review-bundle-tamper"
    )
  )
  edit_concept("preferred_name: Reviewed", "preferred_name: Tampered")
  tampered <- rlang::catch_cnd(graft_commit(store, review))
  expect_s3_class(tampered, "graft_commit_plan_stale")

  graft_sync(store)
  edit_concept("preferred_name: Review base", "preferred_name: Reviewed")
  stale <- graft_review(
    store,
    provenance = graft_provenance(
      "reviewer",
      idempotency_key = "review-store-stale"
    )
  )
  graft_ingest(
    store,
    list(
      Entity = data.frame(
        id = "graft:00000000000000000000000003",
        preferred_name = "Concurrent"
      )
    ),
    graft_provenance("concurrent", idempotency_key = "concurrent")
  )
  stale_error <- rlang::catch_cnd(graft_commit(store, stale))
  expect_s3_class(stale_error, "graft_commit_plan_stale")
})
