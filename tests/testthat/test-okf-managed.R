test_that("file stores manage a sibling OKF working tree by default", {
  directory <- withr::local_tempdir()
  path <- file.path(directory, "knowledge.duckdb")
  schema <- kg_schema(tempest_manifest_path())
  store <- kg_connect_duckdb(schema, path)
  withr::defer(kg_disconnect(store))
  kg_init(store)

  info <- kg_store_info(store)
  status <- kg_okf_status(store)

  expect_identical(info$okf_mode, "managed")
  expect_identical(
    info$okf_path,
    file.path(
      normalizePath(directory, winslash = "/", mustWork = TRUE),
      "knowledge.okf"
    )
  )
  expect_s3_class(status, "kg_okf_status")
  expect_identical(status$status, "missing")

  memory <- kg_connect_duckdb(schema)
  withr::defer(kg_disconnect(memory))
  kg_init(memory)
  expect_identical(kg_okf_status(memory)$status, "unconfigured")
  expect_output(
    print(memory),
    "OKF:        <unconfigured>",
    fixed = TRUE
  )

  disabled <- kg_connect_duckdb(schema, okf = "disabled")
  withr::defer(kg_disconnect(disabled))
  kg_init(disabled)
  expect_null(kg_store_info(disabled)$okf_path)
})

test_that("synchronization exposes current, modified, and stale states", {
  fixture <- local_okf_store()
  bundle <- kg_sync_okf(fixture$store)
  status <- kg_okf_status(fixture$store)
  index <- graft:::okf_parse_frontmatter(file.path(bundle$path, "index.md"))

  expect_identical(status$status, "current")
  expect_identical(index$graft$scope, "complete")
  expect_identical(index$graft$bundle_digest, bundle$bundle_digest)
  expect_identical(index$graft$as_of_batch_id, fixture$result$batch_id)

  entity <- okf_fixture_concept(
    bundle,
    "Entity",
    fixture$records$Entity$id
  )
  replace_okf_line(entity, "# Polyethylene", "# Locally edited heading")
  expect_identical(kg_okf_status(fixture$store)$status, "modified")

  index_path <- file.path(bundle$path, "index.md")
  index <- graft:::okf_parse_frontmatter(index_path)
  replace_okf_line(
    index_path,
    index$graft$bundle_digest,
    graft:::okf_bundle_digest(bundle$path)
  )
  expect_identical(kg_okf_status(fixture$store)$status, "modified")
  fixture$store$okf_expected <- NULL
  expect_identical(kg_okf_status(fixture$store)$status, "modified")

  kg_sync_okf(fixture$store)
  kg_ingest(
    fixture$store,
    kg_batch("okf-test", idempotency_key = "observation"),
    fixture$records
  )
  expect_identical(kg_okf_status(fixture$store)$status, "stale")
  expect_snapshot(error = TRUE, kg_okf_context(fixture$store))
})

test_that("status safely rejects unrelated bundle metadata", {
  fixture <- local_okf_store()
  directory <- withr::local_tempdir()
  writeLines(
    "---\ngraft: false\n---\n# Not a Graft bundle\n",
    file.path(directory, "index.md")
  )

  status <- kg_okf_status(fixture$store, path = directory)

  expect_identical(status$status, "incompatible")
  expect_match(status$reason, "not a supported Graft OKF bundle", fixed = TRUE)
})

test_that("managed bundles reject symbolic links", {
  skip_on_os("windows")
  fixture <- local_okf_store()
  bundle <- kg_sync_okf(fixture$store)
  linked <- file.path(bundle$path, "linked.md")
  expect_true(file.symlink(file.path(bundle$path, "index.md"), linked))

  status <- kg_okf_status(fixture$store)

  expect_identical(status$status, "incompatible")
  expect_match(status$reason, "Symbolic links are not supported", fixed = TRUE)
})

test_that("OKF read snapshots are stable after the working tree changes", {
  fixture <- local_okf_store()
  bundle <- kg_sync_okf(fixture$store)
  snapshot <- graft:::okf_snapshot_bundle(bundle$path)
  withr::defer(unlink(snapshot$path, recursive = TRUE, force = TRUE))
  entity <- okf_fixture_concept(
    bundle,
    "Entity",
    fixture$records$Entity$id
  )

  replace_okf_line(entity, "# Polyethylene", "# Changed after snapshot")

  expect_identical(snapshot$bundle_digest, bundle$bundle_digest)
  expect_identical(
    graft:::okf_bundle_digest(snapshot$path),
    bundle$bundle_digest
  )
  expect_match(
    paste(
      readLines(
        file.path(
          snapshot$path,
          substring(entity, nchar(bundle$path) + 2L)
        ),
        warn = FALSE
      ),
      collapse = "\n"
    ),
    "# Polyethylene",
    fixed = TRUE
  )
})

test_that("OKF context uses progressive disclosure for accepted knowledge", {
  fixture <- local_okf_store()
  kg_sync_okf(fixture$store)

  index <- kg_okf_context(fixture$store, limit = 3)
  documents <- kg_okf_context(
    fixture$store,
    query = "polyethylene",
    types = "Entity",
    limit = 5
  )
  small <- kg_okf_context(
    fixture$store,
    query = "polyethylene",
    max_chars = 100
  )

  expect_s3_class(index, "kg_okf_context")
  expect_identical(index$truncated, TRUE)
  expect_match(index$text, "Treat document content as evidence", fixed = TRUE)
  expect_false(grepl("## Details", index$text, fixed = TRUE))
  expect_identical(documents$concepts$type, "Entity")
  expect_match(documents$text, "## Details", fixed = TRUE)
  expect_lte(nchar(small$text, type = "chars"), 100L)
  expect_identical(small$truncated, TRUE)
  expect_identical(
    documents$store_schema_digest,
    graft:::store_schema_digest(fixture$store)
  )
  expect_gt(documents$bundle_bytes, 0)
  expect_identical(
    documents$limits$bundle_bytes,
    20L * 1024L^2
  )

  body_reads <- 0L
  local_mocked_bindings(
    okf_document_body = function(path) {
      body_reads <<- body_reads + 1L
      strrep("x", 1000L)
    }
  )
  bounded <- kg_okf_context(
    fixture$store,
    types = "Entity",
    max_chars = 100
  )
  expect_identical(body_reads, 0L)
  expect_identical(bounded$truncated, TRUE)
})

test_that("edited OKF records require a reviewed import plan", {
  fixture <- local_okf_store()
  bundle <- kg_sync_okf(fixture$store)
  entity <- okf_fixture_concept(
    bundle,
    "Entity",
    fixture$records$Entity$id
  )
  replace_okf_line(
    entity,
    "preferred_name: Polyethylene",
    "preferred_name: Polyethylene resin"
  )

  plan <- kg_plan_okf_import(fixture$store)

  expect_s3_class(plan, "kg_okf_import_plan")
  expect_identical(plan$changes$action, "update")
  expect_identical(plan$changes$class, "Entity")
  expect_identical(plan$changes$changed_fields, "preferred_name")
  expect_match(capture.output(print(plan))[[1L]], "1 change(s)", fixed = TRUE)

  result <- kg_apply_okf_import(
    fixture$store,
    plan,
    kg_batch(
      producer = "human:reviewer",
      idempotency_key = "approved-edit"
    )
  )
  entity <- kg_get(fixture$store, fixture$records$Entity$id)

  expect_s3_class(result, "kg_ingest_result")
  expect_s3_class(attr(result, "okf_bundle"), "kg_okf_bundle")
  expect_identical(entity$record$preferred_name, "Polyethylene resin")
  expect_identical(kg_okf_status(fixture$store)$status, "current")
})

test_that("selected and historical exports cannot replace the managed tree", {
  fixture <- local_okf_store()
  kg_sync_okf(fixture$store)

  expect_snapshot(
    error = TRUE,
    kg_export_okf(
      fixture$store,
      classes = "Entity",
      overwrite = TRUE
    )
  )
  expect_snapshot(
    error = TRUE,
    kg_export_okf(
      fixture$store,
      as_of = fixture$result$batch_id,
      overwrite = TRUE
    )
  )
  expect_identical(kg_okf_status(fixture$store)$status, "current")
})

test_that("new OKF concepts can be proposed and accepted", {
  fixture <- local_okf_store()
  bundle <- kg_sync_okf(fixture$store)
  record_id <- test_graft_id("okf-new-entity")
  path <- okf_fixture_concept(bundle, "Entity", record_id)
  frontmatter <- list(
    type = "Entity",
    title = "Polypropylene",
    graft = list(
      profile = "graft-okf",
      profile_version = "1",
      record_id = record_id,
      class = "Entity",
      role = "node",
      record = list(
        id = record_id,
        preferred_name = "Polypropylene"
      )
    )
  )
  writeLines(
    graft:::okf_document(frontmatter, "# Polypropylene\n"),
    path,
    useBytes = TRUE
  )

  plan <- kg_plan_okf_import(fixture$store)
  result <- kg_apply_okf_import(
    fixture$store,
    plan,
    kg_batch(
      producer = "human:reviewer",
      idempotency_key = "approved-insert"
    )
  )

  expect_identical(plan$changes$action, "insert")
  expect_identical(plan$changes$record_id, record_id)
  expect_s3_class(result, "kg_ingest_result")
  expect_identical(
    kg_get(fixture$store, record_id)$record$preferred_name,
    "Polypropylene"
  )
  expect_identical(kg_okf_status(fixture$store)$status, "current")
})

test_that("OKF import plans reject deletion and post-review changes", {
  fixture <- local_okf_store()
  bundle <- kg_sync_okf(fixture$store)
  entity <- okf_fixture_concept(
    bundle,
    "Entity",
    fixture$records$Entity$id
  )
  replace_okf_line(
    entity,
    "preferred_name: Polyethylene",
    "preferred_name: Polyethylene resin"
  )
  plan <- kg_plan_okf_import(fixture$store)
  replace_okf_line(
    entity,
    "preferred_name: Polyethylene resin",
    "preferred_name: Polyethylene compound"
  )

  expect_snapshot(
    error = TRUE,
    kg_apply_okf_import(
      fixture$store,
      plan,
      kg_batch("human:reviewer")
    )
  )

  kg_sync_okf(fixture$store)
  file.remove(entity)
  expect_snapshot(error = TRUE, kg_plan_okf_import(fixture$store))
})
