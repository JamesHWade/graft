test_that("a closed-store backup restores accepted corrections and pinned history", {
  fixture <- forget_fixture()
  expected <- forget_read(
    fixture$journal,
    fixture$alice$path,
    fixture$manifest,
    function(store) {
      list(
        current = graft_get(store, "knowledge:interpretation"),
        old = graft_get(
          graft_at(store, fixture$alice$original),
          "knowledge:interpretation"
        ),
        history = graft_history(store, "knowledge:interpretation")
      )
    }
  )
  restored <- forget_read(
    fixture$journal,
    fixture$backup,
    fixture$manifest,
    function(store) {
      list(
        current = graft_get(store, "knowledge:interpretation"),
        old = graft_get(
          graft_at(store, fixture$alice$original),
          "knowledge:interpretation"
        ),
        history = graft_history(store, "knowledge:interpretation")
      )
    }
  )
  expect_identical(restored, expected)
  expect_identical(restored$current$record$body, "PRIVATE-FORGET-CORRECTED")
  expect_identical(restored$old$record$body, "PRIVATE-FORGET-ORIGINAL")
  expect_equal(nrow(restored$history), 2L)
})

test_that("the host previews dependent copies while retaining a still-used source", {
  fixture <- forget_fixture()
  selected <- forget_selection(fixture$records, "knowledge:interpretation")
  expect_identical(
    selected,
    c("knowledge:interpretation", "support:interpretation")
  )
  expect_identical(
    forget_selection(fixture$records, "source:trial-v1"),
    sort(c(
      "knowledge:conclusion",
      "knowledge:interpretation",
      "source:trial-v1",
      "support:conclusion",
      "support:interpretation"
    ))
  )
  expect_identical(
    forget_selection(
      fixture$records,
      c("knowledge:conclusion", "knowledge:interpretation")
    ),
    forget_selection(fixture$records, "source:trial-v1")
  )
  unlink(fixture$copies[4L])
  expect_identical(
    forget_open(fixture$alice$path, function(store) {
      graft_get(store, "knowledge:interpretation")$record$body
    }),
    "PRIVATE-FORGET-CORRECTED"
  )
})

test_that("Forget requires exact action approval and retries preserve the decision", {
  fixture <- forget_fixture()
  preview <- forget_preview(
    fixture$journal,
    fixture$records,
    "knowledge:interpretation",
    "request-1"
  )
  before <- forget_journal_read(fixture$journal)
  expect_error(
    forget_accept(fixture$journal, preview, \(plan) FALSE),
    class = "forget_not_authorized"
  )
  wrong <- preview
  wrong$action <- "archive"
  expect_error(
    forget_accept(fixture$journal, wrong, \(plan) TRUE),
    class = "forget_not_authorized"
  )
  expect_identical(forget_journal_read(fixture$journal), before)
  forget_accept(fixture$journal, preview, \(plan) identical(plan, preview))
  accepted <- forget_journal_read(fixture$journal)
  expect_identical(accepted$epoch, 1L)
  forget_accept(fixture$journal, preview, \(plan) FALSE)
  expect_identical(forget_journal_read(fixture$journal), accepted)
  wrong <- preview
  wrong$ids <- "knowledge:preference"
  expect_error(
    forget_accept(fixture$journal, wrong, \(plan) TRUE),
    class = "forget_unavailable"
  )
  expect_error(
    forget_read(
      fixture$journal,
      fixture$backup,
      fixture$manifest,
      graft_snapshot
    ),
    class = "forget_unavailable"
  )
})

test_that("an approval tied to a superseded backup boundary is refused", {
  fixture <- forget_fixture()
  preview <- forget_preview(
    fixture$journal,
    fixture$records,
    "knowledge:interpretation",
    "request-1"
  )
  state <- forget_journal_read(fixture$journal)
  state$manifest$epoch <- 1L
  forget_journal_write(fixture$journal, state)
  expect_error(
    forget_accept(fixture$journal, preview, \(plan) TRUE),
    class = "forget_not_authorized"
  )
})

test_that("crashes and cleanup retries cannot reopen a retired generation", {
  for (stage in c(
    "accepted",
    "candidate_validated",
    "copy_removed",
    "published"
  )) {
    fixture <- forget_fixture()
    bob_before <- forget_open(fixture$bob$path, function(store) {
      graft_get(store, "knowledge:interpretation")
    })
    preview <- forget_preview(
      fixture$journal,
      fixture$records,
      "knowledge:interpretation",
      "request-1"
    )
    forget_accept(fixture$journal, preview, \(plan) identical(plan, preview))
    candidate <- fixture$build("replacement", preview$ids)
    if (stage != "accepted") {
      expect_error(
        forget_finish(
          fixture$journal,
          candidate$path,
          fixture$purge_paths,
          fixture$certify,
          function(point) {
            if (point == stage) forget_error("synthetic_crash")
          }
        ),
        class = "synthetic_crash"
      )
    }
    expect_error(
      forget_read(
        fixture$journal,
        fixture$backup,
        fixture$manifest,
        graft_snapshot
      ),
      class = "forget_unavailable"
    )
    forget_finish(
      fixture$journal,
      candidate$path,
      fixture$purge_paths,
      fixture$certify
    )
    state <- forget_journal_read(fixture$journal)
    forget_finish(
      fixture$journal,
      candidate$path,
      fixture$purge_paths,
      fixture$certify
    )
    expect_identical(forget_journal_read(fixture$journal), state)
    expect_identical(
      file.exists(fixture$purge_paths),
      rep(FALSE, length(fixture$purge_paths))
    )
    expect_identical(file.exists(fixture$backup), TRUE)
    retained <- forget_read(
      fixture$journal,
      candidate$path,
      state$manifest,
      function(store) {
        list(
          record = graft_get(store, "knowledge:conclusion"),
          source = graft_get(store, "source:trial-v1"),
          history = graft_history(store, "knowledge:conclusion"),
          search = graft_find(store, "PRIVATE-FORGET")
        )
      }
    )
    expect_identical(
      retained$record$record$body,
      "Retained accepted correction."
    )
    expect_identical(
      retained$source$record$document_revision,
      "document:synthetic-trial:version-1"
    )
    expect_equal(nrow(retained$history), 2L)
    expect_equal(nrow(retained$search), 0L)
    expect_error(
      forget_read(fixture$journal, candidate$path, state$manifest, \(store) {
        graft_at(store, fixture$alice$original)
      }),
      class = "graft_snapshot_store_mismatch"
    )
    expect_identical(
      forget_open(fixture$bob$path, function(store) {
        graft_get(store, "knowledge:interpretation")
      }),
      bob_before
    )
    # Inspect every logical table, including private revisions and projections.
    connection <- DBI::dbConnect(
      duckdb::duckdb(),
      candidate$path,
      read_only = TRUE
    )
    tables <- lapply(DBI::dbListTables(connection), \(table) {
      DBI::dbReadTable(connection, table)
    })
    DBI::dbDisconnect(connection, shutdown = TRUE)
    expect_identical(
      grepl("PRIVATE-FORGET", canonical_json(tables), fixed = TRUE),
      FALSE
    )
  }
})

test_that("restore requires the independent ledger and the certified image", {
  fixture <- forget_fixture()
  preview <- forget_preview(
    fixture$journal,
    fixture$records,
    "knowledge:interpretation",
    "request-1"
  )
  forget_accept(fixture$journal, preview, \(plan) identical(plan, preview))
  candidate <- fixture$build("replacement", preview$ids)
  forget_finish(
    fixture$journal,
    candidate$path,
    fixture$purge_paths,
    fixture$certify
  )
  state <- forget_journal_read(fixture$journal)
  expect_error(
    forget_read(
      fixture$journal,
      fixture$backup,
      state$manifest,
      graft_snapshot
    ),
    class = "forget_unavailable"
  )
  relabeled <- fixture$manifest
  relabeled$epoch <- 1L
  expect_error(
    forget_read(fixture$journal, fixture$backup, relabeled, graft_snapshot),
    class = "forget_unavailable"
  )
  expect_error(
    forget_read(
      fixture$journal,
      fixture$bob$path,
      state$manifest,
      graft_snapshot
    ),
    class = "forget_unavailable"
  )
  fresh_backup <- file.path(fixture$directory, "fresh-backup.duckdb")
  expect_identical(file.copy(candidate$path, fresh_backup), TRUE)
  expect_identical(
    forget_read(fixture$journal, fresh_backup, state$manifest, \(store) {
      S7::props(graft_snapshot(store))
    }),
    state$manifest$snapshot
  )
  expect_identical(
    grepl("PRIVATE-FORGET", canonical_json(state), fixed = TRUE),
    FALSE
  )
  missing <- file.path(fixture$directory, "missing-journal")
  expect_error(
    forget_read(missing, fresh_backup, state$manifest, graft_snapshot),
    class = "forget_unavailable"
  )
})

test_that("a fresh worker and an in-flight read honor the current Forget decision", {
  fixture <- forget_fixture()
  preview <- forget_preview(
    fixture$journal,
    fixture$records,
    "knowledge:interpretation",
    "request-1"
  )
  result <- "not released"
  expect_error(
    result <- forget_read(
      fixture$journal,
      fixture$backup,
      fixture$manifest,
      function(store) {
        value <- graft_get(store, "knowledge:interpretation")
        forget_accept(fixture$journal, preview, \(plan) {
          identical(plan, preview)
        })
        value
      }
    ),
    class = "forget_unavailable"
  )
  expect_identical(result, "not released")
  helper <- normalizePath(test_path("helper-forget-restore.R"))
  outcome <- callr::r(
    function(helper, journal, backup, manifest) {
      library(graft)
      source(helper, local = TRUE)
      tryCatch(
        forget_read(journal, backup, manifest, graft_snapshot),
        error = \(error) class(error)[1L]
      )
    },
    args = list(helper, fixture$journal, fixture$backup, fixture$manifest)
  )
  expect_identical(outcome, "forget_unavailable")
})

test_that("uncertified replacements and corrupt replacement backups keep access blocked", {
  fixture <- forget_fixture()
  preview <- forget_preview(
    fixture$journal,
    fixture$records,
    "knowledge:interpretation",
    "request-1"
  )
  forget_accept(fixture$journal, preview, \(plan) identical(plan, preview))
  contaminated <- fixture$build("contaminated")
  expect_error(
    forget_finish(
      fixture$journal,
      contaminated$path,
      fixture$purge_paths,
      fixture$certify
    ),
    class = "forget_unavailable"
  )
  candidate <- fixture$build("replacement", preview$ids)
  writeLines("incomplete backup", paste0(candidate$path, ".backup"))
  expect_error(
    forget_finish(
      fixture$journal,
      candidate$path,
      fixture$purge_paths,
      fixture$certify
    ),
    class = "forget_unavailable"
  )
  expect_identical(forget_journal_read(fixture$journal)$status, "blocked")
  expect_identical(file.exists(fixture$alice$path), TRUE)
  expect_error(
    forget_read(
      fixture$journal,
      fixture$backup,
      fixture$manifest,
      graft_snapshot
    ),
    class = "forget_unavailable"
  )
})
