test_that("a local closed backup restores complete history and reopens in a new process", {
  source_path <- withr::local_tempdir()
  source <- graft_store(source_path, create = TRUE)
  fixture <- artifact_recovery_fixture(source)

  orphan <- charToRaw("orphan bytes retained in the closed image")
  orphan_digest <- digest::digest(orphan, algo = "sha256", serialize = FALSE)
  writeBin(orphan, file.path(source@path, "content", orphan_digest))
  source_manifest <- graft_manifest(source)

  backup_parent <- withr::local_tempdir()
  backup_path <- file.path(backup_parent, "closed-backup")
  receipt <- graft_backup(
    source,
    backup_path,
    scope = "reader-a",
    generation = "reader-a-generation-1"
  )
  expect_identical(
    graft_verify_backup(backup_path, receipt),
    receipt
  )
  expect_identical(receipt$manifest, source_manifest$id)

  target_parent <- withr::local_tempdir()
  target_path <- file.path(target_parent, "restored")
  target <- graft_store(target_path, create = TRUE)
  restored_manifest <- graft_restore(
    backup_path,
    target,
    receipt
  )
  expect_identical(restored_manifest, source_manifest)

  reopened <- graft_store(target_path)
  expect_identical(graft_manifest(reopened), source_manifest)
  expect_identical(
    artifact_read(reopened, fixture$shared),
    artifact_read(source, fixture$shared)
  )
  expect_identical(
    artifact_read(reopened, fixture$forgotten),
    artifact_read(source, fixture$forgotten)
  )
  expect_identical(
    artifact_read_decision(reopened, "mixed-stream"),
    fixture$mixed_second
  )
  expect_identical(
    artifact_read_decision(
      reopened,
      "mixed-stream",
      fixture$mixed_first$id
    ),
    fixture$mixed_first
  )
  expect_identical(
    readBin(
      file.path(reopened@path, "content", orphan_digest),
      what = "raw",
      n = length(orphan)
    ),
    orphan
  )
  expect_identical(graft_manifest(source), source_manifest)

  process_target <- file.path(
    withr::local_tempdir(),
    "independent-process-restored"
  )
  independent <- callr::r(
    function(checkout, path, expected, target_path) {
      if (!is.null(checkout)) {
        pkgload::load_all(checkout, quiet = TRUE)
      }
      checked <- graft::graft_verify_backup(path, expected)
      target <- graft::graft_store(target_path, create = TRUE)
      restored <- graft::graft_restore(path, target, expected)
      reopened <- graft::graft_store(target_path)
      list(
        receipt = checked,
        restore = restored,
        manifest = graft::graft_manifest(reopened),
        decision = graft:::artifact_read_decision(
          reopened,
          "mixed-stream"
        )
      )
    },
    args = list(
      checkout = if (pkgload::is_dev_package("graft")) {
        normalizePath(test_path("../.."))
      } else {
        NULL
      },
      path = backup_path,
      expected = receipt,
      target_path = process_target
    )
  )
  expect_identical(independent$receipt, receipt)
  expect_identical(independent$restore, source_manifest)
  expect_identical(independent$manifest, source_manifest)
  expect_identical(independent$decision, fixture$mixed_second)
})

test_that("a local backup restores into a committed PostgreSQL scope without crossing isolation", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  fixture <- artifact_recovery_fixture(source)
  source_manifest <- graft_manifest(source)
  backup_path <- file.path(withr::local_tempdir(), "local-backup")
  receipt <- graft_backup(
    source,
    backup_path,
    scope = "reader-a",
    generation = "reader-a-generation-1"
  )

  connection <- local_artifact_postgres()
  DBI::dbWithTransaction(connection, {
    target <- graft_store_postgres(
      connection,
      "local-to-postgres",
      create = TRUE
    )
    expect_identical(
      graft_restore(backup_path, target, receipt),
      source_manifest
    )
  })

  DBI::dbWithTransaction(connection, {
    reopened <- graft_store_postgres(
      connection,
      "local-to-postgres"
    )
    expect_identical(graft_manifest(reopened), source_manifest)
    expect_identical(
      artifact_read_decision(reopened, "mixed-stream"),
      fixture$mixed_second
    )

    isolated <- graft_store_postgres(
      connection,
      "independent-scope",
      create = TRUE
    )
    artifact_save(
      isolated,
      "independent",
      charToRaw("independent scope"),
      "text/plain"
    )
    expect_error(
      artifact_read(isolated, fixture$shared),
      class = "graft_artifact_error"
    )
    expect_length(graft_manifest(isolated)$objects, 2L)
  })
})

test_that("a committed PostgreSQL backup restores into a reopened local store", {
  backup_path <- file.path(withr::local_tempdir(), "postgres-backup")
  connection <- local_artifact_postgres()
  scope <- "postgres-source"

  DBI::dbWithTransaction(connection, {
    source <- graft_store_postgres(
      connection,
      scope,
      create = TRUE
    )
    fixture <- artifact_recovery_fixture(source)
    source_manifest <- graft_manifest(source)
  })

  # Capture the bundle from a committed source transaction. The separate
  # rollback test below covers the intentionally different uncommitted case.
  DBI::dbWithTransaction(connection, {
    source <- graft_store_postgres(connection, scope)
    receipt <- graft_backup(
      source,
      backup_path,
      scope = "reader-a",
      generation = "reader-a-generation-2"
    )
    expect_identical(
      graft_verify_backup(backup_path, receipt),
      receipt
    )
  })

  target_path <- withr::local_tempdir()
  target <- graft_store(target_path, create = TRUE)
  expect_identical(
    graft_restore(backup_path, target, receipt),
    source_manifest
  )
  reopened <- graft_store(target_path)
  expect_identical(graft_manifest(reopened), source_manifest)
  expect_identical(
    artifact_read_decision(reopened, "mixed-stream"),
    fixture$mixed_second
  )

  DBI::dbWithTransaction(connection, {
    source <- graft_store_postgres(connection, scope)
    expect_identical(graft_manifest(source), source_manifest)

    isolated <- graft_store_postgres(
      connection,
      "other-postgres-scope",
      create = TRUE
    )
    expect_length(graft_manifest(isolated)$objects, 0L)
    expect_error(
      artifact_read(isolated, fixture$shared),
      class = "graft_artifact_error"
    )
  })
})

test_that("a PostgreSQL backup made before rollback remains a mechanically verifiable image", {
  backup_path <- file.path(withr::local_tempdir(), "rolled-back-backup")
  connection <- local_artifact_postgres()
  scope <- "rolled-back-source"

  DBI::dbBegin(connection)
  source <- graft_store_postgres(connection, scope, create = TRUE)
  fixture <- artifact_recovery_fixture(source)
  uncommitted_manifest <- graft_manifest(source)
  receipt <- graft_backup(
    source,
    backup_path,
    scope = "reader-a",
    generation = "reader-a-uncommitted"
  )
  expect_identical(
    graft_verify_backup(backup_path, receipt),
    receipt
  )
  DBI::dbRollback(connection)

  # The bundle is a closed byte image, so it remains verifiable after the
  # source transaction is rolled back. This does not establish source commit.
  expect_identical(
    graft_verify_backup(backup_path, receipt),
    receipt
  )
  expect_identical(
    DBI::dbExistsTable(connection, "graft_artifact_objects"),
    FALSE
  )

  target_path <- withr::local_tempdir()
  target <- graft_store(target_path, create = TRUE)
  expect_identical(
    graft_restore(backup_path, target, receipt),
    uncommitted_manifest
  )
  reopened <- graft_store(target_path)
  expect_identical(graft_manifest(reopened), uncommitted_manifest)
  expect_identical(
    artifact_read_decision(reopened, "mixed-stream"),
    fixture$mixed_second
  )
})

test_that("restore rejects an external receipt mismatch before target writes", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  fixture <- artifact_recovery_fixture(source)
  source_manifest <- graft_manifest(source)
  backup_path <- file.path(withr::local_tempdir(), "receipt-backup")
  receipt <- graft_backup(
    source,
    backup_path,
    scope = "reader-a",
    generation = "reader-a-generation-1"
  )

  wrong <- receipt
  wrong$generation <- "reader-a-generation-retired"
  expect_error(
    graft_verify_backup(backup_path, wrong),
    class = "graft_artifact_error"
  )

  target <- graft_store(withr::local_tempdir(), create = TRUE)
  expect_error(
    graft_restore(backup_path, target, wrong),
    class = "graft_artifact_error"
  )
  expect_identical(
    graft_manifest(target)$objects,
    list()
  )

  # A matching old receipt can still restore mechanically. The independent
  # host registry must deny using that generation afterwards.
  old_target <- graft_store(withr::local_tempdir(), create = TRUE)
  expect_identical(
    graft_restore(backup_path, old_target, receipt),
    source_manifest
  )
  journal_path <- file.path(withr::local_tempdir(), "host-journal.rds")
  artifact_recovery_synthetic_write_journal(
    journal_path,
    list(
      format = "synthetic-host-journal/1",
      reader = "reader-a",
      retired_generations = receipt$generation,
      published = NULL
    )
  )
  admission <- artifact_recovery_synthetic_admit(
    journal_path,
    receipt$generation,
    fixture$survivor,
    store = old_target,
    expected_reader = receipt$scope
  )
  expect_identical(admission$admitted, FALSE)
  expect_identical(admission$reason, "generation-retired")
})

test_that("a failed restore stays quarantined and a fresh local target can retry", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  artifact_recovery_fixture(source)
  source_manifest <- graft_manifest(source)
  backup_path <- file.path(withr::local_tempdir(), "retry-backup")
  receipt <- graft_backup(
    source,
    backup_path,
    scope = "reader-a",
    generation = "reader-a-generation-1"
  )

  failed <- graft_store(withr::local_tempdir(), create = TRUE)
  writes <- 0L
  original_put <- artifact_storage_put
  local_mocked_bindings(
    artifact_storage_put = function(store, kind, key, bytes, limit) {
      writes <<- writes + 1L
      if (writes == 4L) {
        artifact_abort("synthetic interrupted restore")
      }
      original_put(store, kind, key, bytes, limit)
    }
  )
  expect_error(
    graft_restore(backup_path, failed, receipt),
    class = "graft_artifact_error"
  )
  expect_gt(writes, 1L)
  expect_gt(length(graft_manifest(failed)$objects), 0L)
  local_mocked_bindings(artifact_storage_put = original_put)
  expect_error(
    graft_restore(backup_path, failed, receipt),
    class = "graft_artifact_error"
  )

  retry <- graft_store(withr::local_tempdir(), create = TRUE)
  expect_identical(
    graft_restore(backup_path, retry, receipt),
    source_manifest
  )
  expect_identical(graft_manifest(retry), source_manifest)
})

test_that("a failed PostgreSQL restore rolls back and retries in a fresh scope", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  artifact_recovery_fixture(source)
  source_manifest <- graft_manifest(source)
  backup_path <- file.path(withr::local_tempdir(), "postgres-retry-backup")
  receipt <- graft_backup(
    source,
    backup_path,
    scope = "reader-a",
    generation = "reader-a-generation-1"
  )

  connection <- local_artifact_postgres()
  failed_scope <- "postgres-failed-target"
  DBI::dbWithTransaction(connection, {
    graft_store_postgres(connection, failed_scope, create = TRUE)
  })

  DBI::dbBegin(connection)
  failed <- graft_store_postgres(connection, failed_scope)
  writes <- 0L
  original_put <- artifact_storage_put
  local_mocked_bindings(
    artifact_storage_put = function(store, kind, key, bytes, limit) {
      writes <<- writes + 1L
      if (writes == 4L) {
        artifact_abort("synthetic interrupted PostgreSQL restore")
      }
      original_put(store, kind, key, bytes, limit)
    }
  )
  expect_error(
    graft_restore(backup_path, failed, receipt),
    class = "graft_artifact_error"
  )
  expect_gt(writes, 1L)
  rows <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT count(*) AS n FROM graft_artifact_objects",
      "WHERE scope = $1 AND kind <> 'store'"
    ),
    params = list(failed_scope)
  )$n[[1L]]
  expect_gt(as.numeric(rows), 0)
  local_mocked_bindings(artifact_storage_put = original_put)
  DBI::dbRollback(connection)

  DBI::dbWithTransaction(connection, {
    reopened <- graft_store_postgres(connection, failed_scope)
    expect_identical(graft_manifest(reopened)$objects, list())
  })

  DBI::dbWithTransaction(connection, {
    retry <- graft_store_postgres(
      connection,
      "postgres-fresh-target",
      create = TRUE
    )
    expect_identical(
      graft_restore(backup_path, retry, receipt),
      source_manifest
    )
  })
})

test_that("an interrupted backup leaves no requested bundle and can retry", {
  source_path <- withr::local_tempdir()
  source <- graft_store(source_path, create = TRUE)
  artifact_recovery_fixture(source)
  backup_parent <- withr::local_tempdir()
  backup_path <- file.path(backup_parent, "interrupted-backup")
  checkout <- if (pkgload::is_dev_package("graft")) {
    normalizePath(test_path("../.."))
  } else {
    NULL
  }

  child_error <- tryCatch(
    callr::r(
      function(checkout, source_path, backup_path) {
        if (!is.null(checkout)) {
          pkgload::load_all(checkout, quiet = TRUE)
        }
        original_put <- graft:::artifact_storage_put
        writes <- 0L
        testthat::local_mocked_bindings(
          artifact_storage_put = function(store, kind, key, bytes, limit) {
            writes <<- writes + 1L
            if (writes == 4L) {
              q(status = 17L, runLast = FALSE)
            }
            original_put(store, kind, key, bytes, limit)
          }
        )
        graft::graft_backup(
          graft::graft_store(source_path),
          backup_path,
          scope = "reader-a",
          generation = "reader-a-interrupted"
        )
      },
      args = list(
        checkout = checkout,
        source_path = source_path,
        backup_path = backup_path
      ),
      timeout = 30
    ),
    error = identity
  )
  expect_s3_class(child_error, "callr_status_error")
  expect_identical(child_error$status, 17L)
  expect_identical(file.exists(backup_path), FALSE)
  staging <- list.files(
    backup_parent,
    all.files = TRUE,
    no.. = TRUE,
    full.names = TRUE
  )
  expect_gt(length(staging), 0L)
  staged_entries <- unlist(lapply(
    staging[dir.exists(staging)],
    list.files,
    all.files = TRUE,
    no.. = TRUE,
    recursive = TRUE,
    full.names = TRUE
  ))
  expect_gt(length(staged_entries), 1L)

  receipt <- graft_backup(
    source,
    backup_path,
    scope = "reader-a",
    generation = "reader-a-retry"
  )
  expect_identical(
    graft_verify_backup(backup_path, receipt),
    receipt
  )
  expect_identical(
    graft_verify_backup(
      backup_path,
      receipt
    )$manifest,
    graft_manifest(source)$id
  )

  staging_after <- list.files(
    backup_parent,
    all.files = TRUE,
    no.. = TRUE,
    full.names = TRUE
  )
  unlink(setdiff(staging_after, backup_path), recursive = TRUE)
})


test_that("backups retain both vocabulary releases across a correction", {
  first <- local_vocabulary("v1")
  second <- local_vocabulary("v2")
  source <- first$store
  selection_v1 <- vocabulary_publish(source, first$path)
  selection_v2 <- vocabulary_publish(source, second$path)
  expected_v1 <- vocabulary_read(source, selection_v1)
  expected_v2 <- vocabulary_read(source, selection_v2)
  path <- file.path(withr::local_tempdir(), "vocabulary-backup")
  receipt <- graft_backup(source, path, "reader", "generation")
  target <- graft_store(withr::local_tempdir(), create = TRUE)
  expect_identical(
    graft_restore(path, target, receipt),
    graft_manifest(source)
  )
  reopened <- graft_store(target@path)
  expect_identical(vocabulary_read(reopened, selection_v1), expected_v1)
  expect_identical(vocabulary_read(reopened, selection_v2), expected_v2)
})
