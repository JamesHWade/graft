test_that("local replacement removes a complete forgotten closure", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  fixture <- artifact_recovery_fixture(source)

  orphan <- charToRaw("orphan content")
  orphan_digest <- digest::digest(orphan, algo = "sha256", serialize = FALSE)
  local_mocked_bindings(artifact_rename_file = function(from, to) {
    if (basename(dirname(to)) == "revisions") {
      return(FALSE)
    }
    file.rename(from, to)
  })
  expect_error(
    artifact_save(source, "failed-publication", orphan, "text/plain"),
    class = "graft_artifact_error"
  )
  local_mocked_bindings(artifact_rename_file = function(from, to) {
    file.rename(from, to)
  })

  before <- graft_manifest(source)
  orphan_objects <- Filter(
    \(object) {
      identical(object$kind, "content") &&
        identical(object$key, orphan_digest)
    },
    before$objects
  )
  expect_length(orphan_objects, 1L)
  expect_equal(orphan_objects[[1L]]$size, length(orphan))
  expect_identical(orphan_objects[[1L]]$digest, orphan_digest)

  plan <- artifact_recovery_plan(source, fixture)
  expect_identical(plan$source, before)
  expect_match(plan$format, "graft-artifact")
  expect_identical(
    artifact_recovery_ref_keys(plan$forget),
    artifact_recovery_ref_keys(list(fixture$leaf, fixture$forgotten))
  )
  expect_identical(plan$forget_streams, "explicit-stream")
  expect_setequal(
    artifact_recovery_removed_ref_keys(plan),
    artifact_recovery_ref_keys(
      list(fixture$leaf, fixture$dependent, fixture$forgotten)
    )
  )
  expect_setequal(
    plan$removed$selections,
    c(fixture$removed_selection)
  )
  expect_setequal(
    plan$removed$streams,
    c("removed-stream", "mixed-stream", "explicit-stream")
  )

  target_path <- withr::local_tempdir()
  target <- graft_store(target_path, create = TRUE)
  result <- graft_replace(source, target, plan)
  expect_identical(result, plan$target)
  expect_identical(graft_manifest(target), plan$target)
  expect_identical(
    graft_manifest(graft_store(target_path)),
    plan$target
  )

  expect_identical(
    artifact_read(target, fixture$survivor)$bytes,
    charToRaw("survivor bytes")
  )
  expect_identical(
    artifact_read(target, fixture$shared)$bytes,
    charToRaw("shared bytes")
  )
  expect_error(
    artifact_read(target, fixture$leaf),
    class = "graft_artifact_error"
  )
  expect_error(
    artifact_read(target, fixture$dependent),
    class = "graft_artifact_error"
  )
  expect_error(
    artifact_read(target, fixture$forgotten),
    class = "graft_artifact_error"
  )
  expect_error(
    artifact_read_selection(target, fixture$removed_selection),
    class = "graft_artifact_error"
  )
  expect_null(artifact_read_decision(target, "removed-stream"))
  expect_null(artifact_read_decision(target, "mixed-stream"))
  expect_null(artifact_read_decision(target, "explicit-stream"))
  expect_identical(
    artifact_read_decision(target, "retained-stream"),
    fixture$retained_decision
  )
  expect_identical(graft_manifest(source), before)

  target_objects <- artifact_recovery_manifest_keys(plan$target)
  expect_identical(
    any(grepl(paste0("\n", orphan_digest, "$"), target_objects)),
    FALSE
  )
  expect_identical(
    any(grepl(paste0("\n", fixture$forgotten$revision, "$"), target_objects)),
    FALSE
  )
  shared_content <- digest::digest(
    charToRaw("shared bytes"),
    algo = "sha256",
    serialize = FALSE
  )
  expect_identical(
    any(grepl(paste0("^content\n", shared_content, "$"), target_objects)),
    TRUE
  )
})

test_that("local replacement failure leaves a quarantine that requires a new target", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  fixture <- artifact_recovery_fixture(source)
  plan <- artifact_recovery_plan(source, fixture)

  partial_path <- withr::local_tempdir()
  partial <- graft_store(
    partial_path,
    create = TRUE,
    max_revision_bytes = 1
  )
  expect_error(
    graft_replace(source, partial, plan),
    class = "graft_artifact_error"
  )
  expect_gt(length(list.files(partial_path, recursive = TRUE)), 1L)
  expect_error(
    graft_replace(source, partial, plan),
    class = "graft_artifact_error"
  )

  retry <- graft_store(withr::local_tempdir(), create = TRUE)
  expect_identical(graft_replace(source, retry, plan), plan$target)
  expect_identical(graft_manifest(retry), plan$target)
})

test_that("local replacement copies exact survivors into isolated PostgreSQL scopes", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  fixture <- artifact_recovery_fixture(source)
  before <- graft_manifest(source)
  plan <- artifact_recovery_plan(source, fixture)

  connection <- local_artifact_postgres()
  schema <- DBI::dbGetQuery(
    connection,
    "SELECT current_schema() AS name"
  )$name
  DBI::dbWithTransaction(connection, {
    target <- graft_store_postgres(
      connection,
      "replacement-target",
      create = TRUE
    )
    reader <- graft_store_postgres(
      connection,
      "independent-reader",
      create = TRUE
    )
    reader_fixture <- artifact_recovery_fixture(reader)
    expect_identical(graft_replace(source, target, plan), plan$target)
  })

  independent <- DBI::dbConnect(RPostgres::Postgres())
  withr::defer(DBI::dbDisconnect(independent))
  DBI::dbExecute(
    independent,
    paste(
      "SET search_path TO",
      DBI::dbQuoteIdentifier(independent, schema)
    )
  )
  DBI::dbWithTransaction(independent, {
    reader <- graft_store_postgres(
      independent,
      "independent-reader"
    )
    expect_identical(graft_manifest(reader), before)
    expect_identical(
      artifact_read(reader, reader_fixture$leaf)$bytes,
      charToRaw("leaf bytes")
    )
    expect_identical(
      artifact_read(reader, reader_fixture$dependent)$bytes,
      charToRaw("dependent bytes")
    )
  })

  DBI::dbWithTransaction(connection, {
    target <- graft_store_postgres(connection, "replacement-target")
    expect_identical(graft_manifest(target), plan$target)
    expect_identical(
      artifact_read(target, fixture$survivor)$bytes,
      charToRaw("survivor bytes")
    )
    expect_error(
      artifact_read(target, fixture$leaf),
      class = "graft_artifact_error"
    )
  })
  expect_identical(graft_manifest(source), before)
})

test_that("PostgreSQL replacement copies exact survivors into a reopened local store", {
  connection <- local_artifact_postgres()
  target_path <- withr::local_tempdir()
  target <- graft_store(target_path, create = TRUE)

  DBI::dbWithTransaction(connection, {
    source <- graft_store_postgres(
      connection,
      "postgres-source",
      create = TRUE
    )
    fixture <- artifact_recovery_fixture(source)
    before <- graft_manifest(source)
    plan <- artifact_recovery_plan(source, fixture)
    expect_identical(graft_replace(source, target, plan), plan$target)
  })

  expect_identical(graft_manifest(target), plan$target)
  reopened <- graft_store(target_path)
  expect_identical(graft_manifest(reopened), plan$target)
  expect_identical(
    artifact_read(reopened, fixture$survivor)$bytes,
    charToRaw("survivor bytes")
  )
  expect_error(
    artifact_read(reopened, fixture$leaf),
    class = "graft_artifact_error"
  )

  DBI::dbWithTransaction(connection, {
    source <- graft_store_postgres(connection, "postgres-source")
    expect_identical(graft_manifest(source), before)
    expect_identical(
      artifact_read(source, fixture$leaf)$bytes,
      charToRaw("leaf bytes")
    )
  })
})

test_that("a PostgreSQL host transaction rolls back a failed quarantine copy", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  fixture <- artifact_recovery_fixture(source)
  plan <- artifact_recovery_plan(source, fixture)
  connection <- local_artifact_postgres()
  scope <- "rolled-back-target"

  DBI::dbWithTransaction(connection, {
    graft_store_postgres(connection, scope, create = TRUE)
  })
  DBI::dbBegin(connection)
  target <- graft_store_postgres(
    connection,
    scope,
    create = TRUE,
    max_revision_bytes = 1
  )
  expect_error(
    graft_replace(source, target, plan),
    class = "graft_artifact_error"
  )
  DBI::dbRollback(connection)

  DBI::dbWithTransaction(connection, {
    target <- graft_store_postgres(connection, scope)
    expect_identical(graft_manifest(target)$objects, list())
  })
})

test_that("PostgreSQL manifests reject unknown scoped objects and corruption", {
  connection <- local_artifact_postgres()
  DBI::dbWithTransaction(connection, {
    source <- graft_store_postgres(
      connection,
      "manifest-source",
      create = TRUE
    )
    fixture <- artifact_recovery_fixture(source)
    before <- graft_manifest(source)
  })

  DBI::dbBegin(connection)
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO graft_artifact_objects",
      "(scope, kind, object_key, payload) VALUES ($1, $2, $3, $4)"
    ),
    params = list(
      "manifest-source",
      "unknown",
      "not-a-graft-object",
      list(charToRaw("unknown"))
    )
  )
  unknown <- graft_store_postgres(connection, "manifest-source")
  expect_error(
    graft_manifest(unknown),
    class = "graft_artifact_error"
  )
  DBI::dbRollback(connection)

  DBI::dbBegin(connection)
  payload <- artifact_read(
    graft_store_postgres(connection, "manifest-source"),
    fixture$survivor
  )$metadata$payload
  DBI::dbExecute(
    connection,
    paste(
      "UPDATE graft_artifact_objects SET payload = $1",
      "WHERE scope = $2 AND kind = 'content' AND object_key = $3"
    ),
    params = list(
      list(charToRaw("corrupt")),
      "manifest-source",
      payload
    )
  )
  corrupt <- graft_store_postgres(connection, "manifest-source")
  expect_error(
    graft_manifest(corrupt),
    class = "graft_artifact_error"
  )
  DBI::dbRollback(connection)

  DBI::dbWithTransaction(connection, {
    reopened <- graft_store_postgres(connection, "manifest-source")
    expect_identical(graft_manifest(reopened), before)
  })
})

test_that("a surviving vocabulary release is exact while its forgotten release disappears", {
  fixture_v1 <- local_vocabulary("v1")
  fixture_v2 <- local_vocabulary("v2")
  source <- fixture_v1$store
  selection_v1 <- vocabulary_publish(source, fixture_v1$path)
  selection_v2 <- vocabulary_publish(source, fixture_v2$path)
  forgotten_release <- vocabulary_read(source, selection_v1)
  survivor <- vocabulary_read(source, selection_v2)
  selected_v1 <- artifact_read_selection(source, selection_v1)
  root_v1 <- artifact_read(source, selected_v1$roots[[1L]])
  forgotten <- root_v1$metadata$dependencies[[1L]]
  plan <- graft_plan_replacement(source, forget = list(forgotten))
  before <- graft_manifest(source)

  target <- graft_store(withr::local_tempdir(), create = TRUE)
  expect_identical(graft_replace(source, target, plan), plan$target)
  expect_identical(vocabulary_read(target, selection_v2), survivor)
  expect_error(
    vocabulary_read(target, selection_v1),
    class = "graft_artifact_error"
  )
  expect_identical(graft_manifest(source), before)
  expect_identical(
    vocabulary_read(source, selection_v1),
    forgotten_release
  )
})

test_that("synthetic host admission retires an old backup across a failed retry", {
  # Synthetic protocol proof only: the RDS journal stands in for an
  # independent host journal. This does not prove production durability,
  # secure erasure, or crash recovery.
  producer <- graft_store(withr::local_tempdir(), create = TRUE)
  fixture <- artifact_recovery_fixture(producer)
  producer_manifest <- graft_manifest(producer)
  reader <- graft_store(withr::local_tempdir(), create = TRUE)
  reader_fixture <- artifact_recovery_fixture(reader)
  reader_manifest <- graft_manifest(reader)

  backup_parent <- withr::local_tempdir()
  backup_path <- file.path(backup_parent, "closed-backup")
  dir.create(backup_path)
  producer_entries <- list.files(
    producer@path,
    all.files = TRUE,
    no.. = TRUE,
    full.names = TRUE
  )
  expect_identical(
    unname(vapply(
      producer_entries,
      \(path) file.copy(path, backup_path, recursive = TRUE),
      logical(1)
    )),
    rep(TRUE, length(producer_entries))
  )
  backup <- graft_store(backup_path)
  expect_identical(graft_manifest(backup), producer_manifest)
  expect_identical(
    artifact_read(backup, fixture$survivor)$bytes,
    charToRaw("survivor bytes")
  )

  journal_path <- file.path(withr::local_tempdir(), "host-journal.rds")
  old_generation <- "reader-a-generation-1"
  new_generation <- "reader-a-generation-2"
  missing <- artifact_recovery_synthetic_admit(
    journal_path,
    old_generation,
    fixture$survivor,
    expected_reader = "reader-a"
  )
  expect_identical(missing$admitted, FALSE)
  expect_identical(missing$reason, "missing-journal")

  retired <- list(
    format = "synthetic-host-journal/1",
    reader = "reader-a",
    retired_generations = old_generation,
    published = NULL
  )
  artifact_recovery_synthetic_write_journal(journal_path, retired)
  expect_identical(
    artifact_recovery_synthetic_admit(
      journal_path,
      old_generation,
      fixture$survivor,
      expected_reader = "reader-a"
    )$reason,
    "generation-retired"
  )

  plan <- artifact_recovery_plan(producer, fixture)
  failed_target <- graft_store(
    withr::local_tempdir(),
    create = TRUE,
    max_revision_bytes = 1
  )
  expect_error(
    graft_replace(producer, failed_target, plan),
    class = "graft_artifact_error"
  )
  reloaded <- artifact_recovery_synthetic_read_journal(journal_path)
  expect_identical(reloaded, retired)
  expect_identical(
    artifact_recovery_synthetic_admit(
      journal_path,
      old_generation,
      fixture$survivor,
      expected_reader = "reader-a"
    )$admitted,
    FALSE
  )
  expect_identical(graft_manifest(backup), producer_manifest)
  expect_identical(
    artifact_read(backup, fixture$survivor)$bytes,
    charToRaw("survivor bytes")
  )

  replacement <- graft_store(
    withr::local_tempdir(),
    create = TRUE
  )
  replacement_manifest <- graft_replace(
    producer,
    replacement,
    plan
  )
  expect_identical(replacement_manifest, plan$target)
  expect_error(
    artifact_read(replacement, fixture$leaf),
    class = "graft_artifact_error"
  )
  expect_identical(
    artifact_read(replacement, fixture$survivor)$bytes,
    charToRaw("survivor bytes")
  )

  published <- reloaded
  published$published <- list(
    generation = new_generation,
    manifest = replacement_manifest$id,
    refs = artifact_recovery_ref_keys(list(fixture$shared, fixture$survivor))
  )
  artifact_recovery_synthetic_write_journal(journal_path, published)
  expect_identical(
    artifact_recovery_synthetic_admit(
      journal_path,
      old_generation,
      fixture$survivor,
      expected_reader = "reader-a"
    )$reason,
    "generation-retired"
  )
  old_backup_relabelled <- artifact_recovery_synthetic_admit(
    journal_path,
    new_generation,
    fixture$survivor,
    store = backup,
    expected_reader = "reader-a"
  )
  expect_identical(old_backup_relabelled$admitted, FALSE)
  expect_identical(old_backup_relabelled$reason, "manifest-mismatch")
  expect_identical(
    artifact_recovery_synthetic_admit(
      journal_path,
      new_generation,
      fixture$survivor
    )$reason,
    "missing-binding"
  )
  admitted <- artifact_recovery_synthetic_admit(
    journal_path,
    new_generation,
    fixture$survivor,
    store = replacement,
    expected_reader = "reader-a"
  )
  expect_identical(admitted$admitted, TRUE)
  expect_identical(admitted$ref, fixture$survivor)
  expect_identical(graft_manifest(reader), reader_manifest)
  expect_identical(
    artifact_read(reader, reader_fixture$survivor)$bytes,
    charToRaw("survivor bytes")
  )
})
