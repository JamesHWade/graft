test_that("closed backups verify and restore a complete local store", {
  source <- graft_artifact_store(
    withr::local_tempdir(),
    create = TRUE
  )
  evidence <- graft_artifact_save(
    source,
    "evidence",
    charToRaw("evidence bytes"),
    "text/plain"
  )
  report <- graft_artifact_save(
    source,
    "report",
    charToRaw("report bytes"),
    "text/plain",
    dependencies = list(evidence)
  )
  selection <- graft_artifact_select(source, list(report))
  accepted <- graft_artifact_decide(
    source,
    "report-review",
    "review-1",
    expected = NULL,
    selection = selection,
    action = "accept",
    actor = "reviewer",
    reason = "reviewed",
    purpose = "research"
  )
  source_manifest <- graft_artifact_manifest(source)
  backup_path <- file.path(withr::local_tempdir(), "closed-backup")

  receipt <- graft_artifact_backup(
    source,
    backup_path,
    scope = "reader-a",
    generation = "generation-1"
  )

  expect_identical(
    sort(list.files(backup_path, all.files = TRUE, no.. = TRUE)),
    c("bundle.json", "objects")
  )
  expect_identical(graft_artifact_backup_verify(backup_path, receipt), receipt)
  expect_identical(
    graft_artifact_backup_verify(paste0(backup_path, "/."), receipt),
    receipt
  )
  expect_identical(graft_artifact_manifest(source), source_manifest)

  target <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  restored <- graft_artifact_restore(backup_path, target, receipt)

  expect_identical(restored, source_manifest)
  expect_identical(graft_artifact_manifest(target), source_manifest)
  expect_identical(
    graft_artifact_read(target, report)$bytes,
    charToRaw("report bytes")
  )
  expect_identical(
    graft_artifact_read_decision(target, "report-review"),
    accepted
  )
})

test_that("backup verification requires the external receipt and canonical image", {
  source <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  ref <- graft_artifact_save(
    source,
    "report",
    charToRaw("report bytes"),
    "text/plain"
  )
  backup_path <- file.path(withr::local_tempdir(), "closed-backup")
  receipt <- graft_artifact_backup(source, backup_path, "reader-a", "gen-1")

  wrong <- receipt
  wrong$scope <- "reader-b"
  expect_error(
    graft_artifact_backup_verify(backup_path, wrong),
    class = "graft_artifact_error"
  )

  descriptor_path <- file.path(backup_path, "bundle.json")
  descriptor <- readBin(descriptor_path, "raw", file.info(descriptor_path)$size)
  writeBin(c(descriptor, charToRaw(" ")), descriptor_path)
  expect_error(
    graft_artifact_backup_verify(backup_path, receipt),
    class = "graft_artifact_error"
  )
  writeBin(descriptor, descriptor_path)

  content_path <- file.path(
    backup_path,
    "objects",
    "content",
    graft_artifact_read(source, ref)$metadata$payload
  )
  original <- readBin(content_path, "raw", file.info(content_path)$size)
  writeBin(charToRaw("tampered"), content_path)
  expect_error(
    graft_artifact_backup_verify(backup_path, receipt),
    class = "graft_artifact_error"
  )
  writeBin(original, content_path)

  file.create(file.path(backup_path, "unexpected"))
  expect_error(
    graft_artifact_backup_verify(backup_path, receipt),
    class = "graft_artifact_error"
  )
})

test_that("backup paths cannot overwrite or overlap a source store", {
  source <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  parent <- withr::local_tempdir()
  existing <- file.path(parent, "existing")
  dir.create(existing)
  expect_error(
    graft_artifact_backup(source, existing, "reader", "generation"),
    class = "graft_artifact_error"
  )

  dangling <- file.path(parent, "dangling")
  skip_on_os("windows")
  expect_identical(file.symlink("missing", dangling), TRUE)
  expect_error(
    graft_artifact_backup(
      source,
      paste0(dangling, "/"),
      "reader",
      "generation"
    ),
    class = "graft_artifact_error"
  )

  inside <- file.path(source$path, "backup")
  expect_error(
    graft_artifact_backup(source, inside, "reader", "generation"),
    class = "graft_artifact_error"
  )
  expect_identical(dir.exists(inside), FALSE)
})

test_that("bundle root aliases and special files are rejected before reads", {
  skip_on_os("windows")
  source <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  backup_path <- file.path(withr::local_tempdir(), "closed-backup")
  receipt <- graft_artifact_backup(source, backup_path, "reader", "generation")

  alias <- file.path(withr::local_tempdir(), "alias")
  expect_identical(file.symlink(backup_path, alias), TRUE)
  expect_error(
    graft_artifact_backup_verify(paste0(alias, "/."), receipt),
    class = "graft_artifact_error"
  )

  skip_if(!nzchar(Sys.which("mkfifo")))
  descriptor_path <- file.path(backup_path, "bundle.json")
  unlink(descriptor_path)
  expect_identical(system2("mkfifo", shQuote(descriptor_path)), 0L)
  result <- callr::r(
    function(checkout, path, expected) {
      if (!is.null(checkout)) {
        pkgload::load_all(checkout, quiet = TRUE)
      }
      tryCatch(
        graft::graft_artifact_backup_verify(path, expected),
        graft_artifact_error = function(cnd) class(cnd)[[1L]]
      )
    },
    args = list(
      checkout = if (pkgload::is_dev_package("graft")) {
        normalizePath(testthat::test_path("../.."))
      } else {
        NULL
      },
      path = backup_path,
      expected = receipt
    ),
    timeout = 10
  )
  expect_identical(result, "graft_artifact_error")
})

test_that("backup and verification bounds are caller supplied", {
  source <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  graft_artifact_save(source, "report", charToRaw("report bytes"), "text/plain")
  backup_parent <- withr::local_tempdir()
  too_few <- file.path(backup_parent, "too-few")
  expect_error(
    graft_artifact_backup(
      source,
      too_few,
      "reader",
      "generation",
      max_objects = 1
    ),
    class = "graft_artifact_error"
  )
  expect_identical(dir.exists(too_few), FALSE)

  too_small <- file.path(backup_parent, "too-small")
  expect_error(
    graft_artifact_backup(
      source,
      too_small,
      "reader",
      "generation",
      max_bundle_metadata_bytes = 1
    ),
    class = "graft_artifact_error"
  )
  expect_identical(dir.exists(too_small), FALSE)

  backup_path <- file.path(backup_parent, "closed-backup")
  receipt <- graft_artifact_backup(source, backup_path, "reader", "generation")
  expect_error(
    graft_artifact_backup_verify(backup_path, receipt, max_bytes = 1),
    class = "graft_artifact_error"
  )
})

test_that("backup rechecks a source changed during copying", {
  source <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  graft_artifact_save(source, "report", charToRaw("report bytes"), "text/plain")
  backup_path <- file.path(withr::local_tempdir(), "closed-backup")
  original <- artifact_storage_put
  changed <- FALSE

  local_mocked_bindings(artifact_storage_put = function(
    store,
    kind,
    key,
    bytes,
    limit
  ) {
    result <- original(store, kind, key, bytes, limit)
    if (!changed) {
      changed <<- TRUE
      graft_artifact_save(
        source,
        "changed",
        charToRaw("changed bytes"),
        "text/plain"
      )
    }
    result
  })

  expect_error(
    graft_artifact_backup(source, backup_path, "reader", "generation"),
    class = "graft_artifact_error"
  )
  expect_identical(changed, TRUE)
  expect_identical(dir.exists(backup_path), FALSE)
})

test_that("restore rechecks a target changed during copying", {
  source <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  graft_artifact_save(source, "report", charToRaw("report bytes"), "text/plain")
  backup_path <- file.path(withr::local_tempdir(), "closed-backup")
  receipt <- graft_artifact_backup(source, backup_path, "reader", "generation")
  target <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  original <- artifact_storage_put
  changed <- FALSE

  local_mocked_bindings(artifact_storage_put = function(
    store,
    kind,
    key,
    bytes,
    limit
  ) {
    result <- original(store, kind, key, bytes, limit)
    if (!changed && identical(store$path, target$path)) {
      changed <<- TRUE
      graft_artifact_save(
        target,
        "changed",
        charToRaw("changed bytes"),
        "text/plain"
      )
    }
    result
  })

  expect_error(
    graft_artifact_restore(backup_path, target, receipt),
    class = "graft_artifact_error"
  )
  expect_identical(changed, TRUE)
  expect_gt(length(graft_artifact_manifest(target)$objects), 0L)
  expect_identical(graft_artifact_backup_verify(backup_path, receipt), receipt)
})

test_that("backup copy failures clean up their own staging directory", {
  source <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
  graft_artifact_save(source, "report", charToRaw("report bytes"), "text/plain")
  parent <- withr::local_tempdir()
  backup_path <- file.path(parent, "closed-backup")
  before <- list.files(parent, all.files = TRUE, no.. = TRUE)
  local_mocked_bindings(artifact_storage_put = function(...) {
    artifact_abort("Injected backup copy failure.")
  })
  expect_error(
    graft_artifact_backup(source, backup_path, "reader", "generation"),
    class = "graft_artifact_error"
  )
  expect_identical(
    list.files(parent, all.files = TRUE, no.. = TRUE),
    before
  )
  expect_identical(dir.exists(backup_path), FALSE)
})

test_that("metadata objects use the metadata bound rather than revision bound", {
  source <- graft_artifact_store(
    withr::local_tempdir(),
    create = TRUE,
    max_revision_bytes = 512
  )
  roots <- lapply(seq_len(8L), function(index) {
    graft_artifact_save(
      source,
      paste0("root-", index),
      charToRaw(paste0("root ", index)),
      "text/plain"
    )
  })
  selection <- graft_artifact_select(
    source,
    roots,
    max_metadata_bytes = 64 * 1024
  )
  graft_artifact_decide(
    source,
    "retained",
    "review",
    NULL,
    selection,
    "accept",
    "reviewer",
    paste0(strrep("reason", 100L), "x"),
    "research",
    max_metadata_bytes = 64 * 1024
  )
  backup_path <- file.path(withr::local_tempdir(), "closed-backup")
  receipt <- graft_artifact_backup(source, backup_path, "reader", "generation")
  expect_identical(graft_artifact_backup_verify(backup_path, receipt), receipt)
})


test_that("existing parent aliases resolve before source-overlap checks", {
  skip_on_os("windows")
  parent <- withr::local_tempdir()
  alias <- file.path(withr::local_tempdir(), "parent-alias")
  expect_identical(file.symlink(parent, alias), TRUE)
  source <- graft_artifact_store(file.path(parent, "source"), create = TRUE)
  before <- graft_artifact_manifest(source)
  path <- file.path(alias, "backup")
  receipt <- graft_artifact_backup(source, path, "reader", "generation")
  expect_identical(graft_artifact_backup_verify(path, receipt), receipt)
  expect_error(
    graft_artifact_backup(
      source,
      file.path(alias, "source", "backup"),
      "reader",
      "generation"
    ),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_artifact_backup(
      source,
      file.path(alias, "source", "..", "other"),
      "reader",
      "generation"
    ),
    class = "graft_artifact_error"
  )
  expect_identical(graft_artifact_manifest(source), before)
})


test_that("path containment handles filesystem roots and sibling prefixes", {
  expect_identical(artifact_backup_path_contains("/", "/backup"), TRUE)
  expect_identical(artifact_backup_path_contains("D:/", "D:/backup"), TRUE)
  expect_identical(artifact_backup_path_contains("D:/", "E:/backup"), FALSE)
  expect_identical(artifact_backup_path_contains("/store", "/store-2"), FALSE)
})
