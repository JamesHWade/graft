test_that("BR-27 keeps synchronization explicit and summaries ordinary", {
  directory <- withr::local_tempdir()
  path <- file.path(directory, "knowledge.duckdb")
  schema <- graft_schema(tempest_manifest_path())
  store <- graft_open(schema, path)
  withr::defer(graft_close(store))

  missing <- graft_status(store)

  expect_type(missing, "list")
  expect_identical(is.object(missing), FALSE)
  expect_identical(missing$status, "missing")
  expect_identical(
    missing$path,
    file.path(
      normalizePath(directory, winslash = "/", mustWork = TRUE),
      "knowledge.okf"
    )
  )

  memory <- graft_open(schema, ":memory:", okf = "disabled")
  withr::defer(graft_close(memory))
  expect_identical(graft_status(memory)$status, "unconfigured")

  fixture <- local_okf_store()
  bundle <- graft_sync(fixture$store)
  current <- graft_status(fixture$store)

  expect_type(bundle, "list")
  expect_identical(is.object(bundle), FALSE)
  expect_type(current, "list")
  expect_identical(is.object(current), FALSE)
  expect_identical(current$status, "current")

  graft_ingest(
    fixture$store,
    fixture$records,
    graft_provenance(
      "okf-test",
      idempotency_key = "accepted-after-sync"
    )
  )
  expect_identical(graft_status(fixture$store)$status, "stale")

  graft_sync(fixture$store)
  expect_identical(graft_status(fixture$store)$status, "current")
})

test_that("BR-27 synchronization never replaces an unrelated directory", {
  fixture <- local_okf_store()
  directory <- withr::local_tempdir()
  marker <- file.path(directory, "important.txt")
  writeLines("keep", marker)

  condition <- rlang::catch_cnd(graft_sync(fixture$store, directory))

  expect_s3_class(condition, "graft_backend_error")
  expect_identical(readLines(marker), "keep")
})

test_that("BR-29 synchronization is deterministic and detects edits", {
  fixture <- local_okf_store()
  first <- graft_sync(fixture$store)
  first_files <- list.files(first$path, recursive = TRUE)
  first_text <- vapply(
    file.path(first$path, first_files),
    \(path) paste(readLines(path, warn = FALSE), collapse = "\n"),
    character(1)
  )

  second <- graft_sync(fixture$store)
  second_files <- list.files(second$path, recursive = TRUE)
  second_text <- vapply(
    file.path(second$path, second_files),
    \(path) paste(readLines(path, warn = FALSE), collapse = "\n"),
    character(1)
  )

  expect_identical(first$bundle_digest, second$bundle_digest)
  expect_identical(first_files, second_files)
  expect_identical(unname(first_text), unname(second_text))

  entity <- okf_fixture_concept(
    second,
    "Entity",
    fixture$records$Entity$id
  )
  replace_okf_line(entity, "# Polyethylene", "# Locally edited heading")
  expect_identical(graft_status(fixture$store)$status, "modified")
})

test_that("BR-29 bundle digests exclude only the self-digest field", {
  fixture <- local_okf_store()
  bundle <- graft_sync(fixture$store)
  index <- file.path(bundle$path, "index.md")
  frontmatter <- graft:::okf_parse_frontmatter(index)
  original <- graft:::okf_bundle_digest(bundle$path)

  replace_okf_line(
    index,
    frontmatter$graft$bundle_digest,
    "sha256:changed-self-digest"
  )
  expect_identical(graft:::okf_bundle_digest(bundle$path), original)

  lines <- readLines(index, warn = FALSE, encoding = "UTF-8")
  writeLines(
    c(lines, "", "bundle_digest: body evidence"),
    index,
    useBytes = TRUE
  )
  changed <- graft:::okf_bundle_digest(bundle$path)
  expect_length(unique(c(original, changed)), 2L)
})

test_that("BR-29 deep status derives accepted state without writing", {
  fixture <- local_okf_store()
  graft_sync(fixture$store)
  legacy <- graft:::as_graft_store_internal(fixture$store)
  legacy$okf_expected <- NULL
  local_mocked_bindings(
    export_okf_bundle = \(...) stop("Unexpected export."),
    okf_write_text = \(...) stop("Unexpected write.")
  )

  status <- graft_status(fixture$store, deep = TRUE)

  expect_identical(status$status, "current")
})

test_that("BR-29 status rejects unrelated metadata and symbolic links", {
  fixture <- local_okf_store()
  directory <- withr::local_tempdir()
  writeLines(
    "---\ngraft: false\n---\n# Not a Graft bundle\n",
    file.path(directory, "index.md")
  )

  unrelated <- graft_status(fixture$store, path = directory)

  expect_identical(unrelated$status, "incompatible")
  expect_match(
    unrelated$reason,
    "not a supported Graft OKF bundle",
    fixed = TRUE
  )

  skip_on_os("windows")
  bundle <- graft_sync(fixture$store)
  linked <- file.path(bundle$path, "linked.md")
  expect_identical(
    file.symlink(file.path(bundle$path, "index.md"), linked),
    TRUE
  )

  linked_status <- graft_status(fixture$store)

  expect_identical(linked_status$status, "incompatible")
  expect_match(
    linked_status$reason,
    "Symbolic links are not supported",
    fixed = TRUE
  )
})

test_that("BR-29 OKF review uses the shared commit plan", {
  fixture <- local_okf_store()
  bundle <- graft_sync(fixture$store)
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

  plan <- graft_review(
    fixture$store,
    provenance = graft_provenance(
      "human:reviewer",
      idempotency_key = "approved-edit"
    )
  )
  result <- graft_commit(fixture$store, plan)
  entity_record <- graft_get(
    fixture$store,
    fixture$records$Entity$id,
    include = character()
  )

  expect_s7_class(plan, graft:::GraftCommitPlan)
  expect_identical(plan@source, "okf")
  expect_identical(plan@changes$action, "update")
  expect_identical(plan@changes$changed_fields, "preferred_name")
  expect_type(result, "list")
  expect_identical(is.object(result), FALSE)
  expect_identical(
    entity_record$record$preferred_name,
    "Polyethylene resin"
  )
  expect_identical(graft_status(fixture$store)$status, "modified")

  graft_sync(fixture$store)
  expect_identical(graft_status(fixture$store)$status, "current")
})

test_that("BR-28 new OKF concepts become ordinary commit-plan inserts", {
  fixture <- local_okf_store()
  bundle <- graft_sync(fixture$store)
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

  plan <- graft_review(
    fixture$store,
    provenance = graft_provenance(
      "human:reviewer",
      idempotency_key = "approved-insert"
    )
  )
  result <- graft_commit(fixture$store, plan)

  expect_s7_class(plan, graft:::GraftCommitPlan)
  expect_identical(plan@changes$action, "insert")
  expect_identical(plan@changes$record_id, record_id)
  expect_type(result, "list")
  expect_identical(
    graft_get(
      fixture$store,
      record_id,
      include = character()
    )$record$preferred_name,
    "Polypropylene"
  )
})

test_that("BR-29 review rejects deletions and post-review file changes", {
  fixture <- local_okf_store()
  bundle <- graft_sync(fixture$store)
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
  plan <- graft_review(
    fixture$store,
    provenance = graft_provenance(
      "human:reviewer",
      idempotency_key = "reviewed-edit"
    )
  )
  replace_okf_line(
    entity,
    "preferred_name: Polyethylene resin",
    "preferred_name: Polyethylene compound"
  )

  changed <- rlang::catch_cnd(graft_commit(fixture$store, plan))

  expect_s3_class(changed, "graft_commit_plan_stale")

  bundle <- graft_sync(fixture$store)
  entity <- okf_fixture_concept(
    bundle,
    "Entity",
    fixture$records$Entity$id
  )
  expect_identical(file.remove(entity), TRUE)

  deleted <- rlang::catch_cnd(graft_review(
    fixture$store,
    provenance = graft_provenance("human:reviewer")
  ))

  expect_s3_class(deleted, "graft_okf_import_error")
  expect_match(conditionMessage(deleted), "Removing OKF concept files")
})

test_that("BR-29 review rejects an accepted-store change", {
  fixture <- local_okf_store()
  bundle <- graft_sync(fixture$store)
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
  plan <- graft_review(
    fixture$store,
    provenance = graft_provenance(
      "human:reviewer",
      idempotency_key = "reviewed-before-store-change"
    )
  )
  graft_ingest(
    fixture$store,
    list(
      Entity = data.frame(
        id = test_graft_id("okf-concurrent"),
        preferred_name = "Concurrent record"
      )
    ),
    graft_provenance(
      "concurrent-workflow",
      idempotency_key = "okf-concurrent"
    )
  )

  condition <- rlang::catch_cnd(graft_commit(fixture$store, plan))

  expect_s3_class(condition, "graft_commit_plan_stale")
})

test_that("BR-29 OKF read snapshots remain stable", {
  fixture <- local_okf_store()
  bundle <- graft_sync(fixture$store)
  snapshot <- graft:::okf_snapshot_bundle(bundle$path)
  withr::defer(unlink(snapshot$path, recursive = TRUE, force = TRUE))
  entity <- okf_fixture_concept(
    bundle,
    "Entity",
    fixture$records$Entity$id
  )

  replace_okf_line(entity, "# Polyethylene", "# Changed after snapshot")

  expect_type(snapshot, "list")
  expect_identical(is.object(snapshot), FALSE)
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

test_that("OKF absolute paths include Windows network shares", {
  expect_identical(graft:::okf_is_absolute_path("/tmp/bundle.okf"), TRUE)
  expect_identical(
    graft:::okf_is_absolute_path("C:\\exports\\bundle.okf"),
    TRUE
  )
  expect_identical(
    graft:::okf_is_absolute_path("\\\\server\\share\\bundle.okf"),
    TRUE
  )
  expect_identical(
    graft:::okf_is_absolute_path("exports/bundle.okf"),
    FALSE
  )

  parent <- withr::local_tempdir()
  expected <- file.path(
    normalizePath(parent, winslash = "/", mustWork = TRUE),
    "bundle.okf"
  )
  trailing <- paste0(expected, .Platform$file.sep)
  expect_identical(graft:::okf_normalize_path(trailing), expected)
  expect_identical(graft:::okf_output_path(trailing), expected)
})
