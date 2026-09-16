# Source-side fixture only. Uses Tempest's shipped completed-product bundles and
# public promotion APIs. Native RDS checkpoints stay in this synthetic source;
# the target importer reads only explicit JSON and content bytes.
migration_plain <- function(value) {
  encode <- function(value) {
    if (inherits(value, "POSIXt")) {
      return(list(
        type = "POSIXct",
        epoch_hex = sprintf("%a", as.numeric(value)),
        timezone = attr(value, "tzone")
      ))
    }
    if (inherits(value, "Date")) {
      return(list(type = "Date", days = as.numeric(value)))
    }
    if (is.list(value)) {
      return(lapply(value, encode))
    }
    value
  }
  jsonlite::fromJSON(artifact_json(encode(value)), simplifyVector = FALSE)
}

migration_properties <- function(value) migration_plain(S7::props(value))

migration_resources <- function(knowledge) {
  # Tempest gives each materialization a fresh retrieval timestamp. Compare the
  # retained evidence content/identity, not that new read event's clock.
  fields <- c(
    "resource_id",
    "resource_kind",
    "locator",
    "title",
    "media_type",
    "content",
    "content_hash",
    "metadata"
  )
  lapply(knowledge@records, function(resource) {
    migration_properties(resource)[fields]
  })
}

migration_recipe <- function() {
  recipe <- new.env(parent = baseenv())
  sys.source(
    system.file("examples/briefing-basis.R", package = "tempest"),
    recipe
  )
  recipe
}

migration_produce <- function(directory) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  recipe <- migration_recipe()
  fixture <- system.file("examples/accepted-research", package = "tempest")
  pins <- c(
    initial = "sha256:b19dedc6127d20c515af3bcb9bae9c960bb04cf4a05af5ffafa259f7acf8c43d",
    correction = "sha256:55485f222bdcaf8aa7fa3233184029fb7aad472cfcee4a01250f727f3c5cbc1a"
  )
  store <- graft::graft_open(
    tempest::tempest_graft_schema(),
    file.path(directory, "source.duckdb"),
    okf = "disabled"
  )
  on.exit(graft::graft_close(store), add = TRUE)
  accept <- function(day) {
    bundle <- tempest::tempest_read_promotion_bundle(
      file.path(fixture, day),
      expected_bundle_id = pins[[day]]
    )
    plan <- tempest::tempest_graft_plan(store, bundle)
    commit <- graft::graft_commit(store, plan)
    list(
      plan = plan,
      snapshot = graft::graft_snapshot(store),
      receipt = tempest::tempest_promotion_receipt(store, bundle, plan, commit)
    )
  }
  report <- function(day) {
    rawToChar(artifact_read_bytes(file.path(
      fixture,
      paste0(day, "-report.md")
    )))
  }
  initial <- accept("initial")
  first <- recipe$capture_briefing_basis(
    store,
    list(recipe$briefing_selection(initial$receipt)),
    report("initial")
  )
  original <- migration_resources(recipe$read_briefing_basis(store, first))
  unchanged <- accept("initial")
  stopifnot(
    all(unchanged$plan@changes$action == "match"),
    nrow(recipe$briefing_changes(store, first)) == 0L,
    identical(
      original,
      migration_resources(recipe$read_briefing_basis(store, first))
    )
  )
  correction <- accept("correction")
  old_claim <- initial$plan@records$Claim
  old_claim$status <- "superseded"
  retire <- graft::graft_plan(
    store,
    list(Claim = old_claim),
    graft::graft_provenance(
      "migration-review",
      idempotency_key = "correct-pilot"
    )
  )
  graft::graft_commit(store, retire)
  corrected <- recipe$capture_briefing_basis(
    store,
    list(recipe$briefing_selection(correction$receipt)),
    report("correction")
  )
  accepted <- list(
    initial = initial,
    unchanged = unchanged,
    correction = correction
  )
  native_receipts <- lapply(accepted, \(value) value$receipt)
  receipts <- lapply(native_receipts, migration_properties)
  saveRDS(
    list(
      receipts = native_receipts,
      snapshots = lapply(accepted, \(value) value$snapshot)
    ),
    file.path(directory, "native-receipts.rds")
  )
  ids <- unique(unlist(lapply(receipts, function(receipt) {
    vapply(
      receipt$record_revisions,
      \(revision) revision$record_id,
      character(1)
    )
  })))
  history <- unlist(
    lapply(ids, function(id) {
      rows <- graft::graft_history(store, id, limit = 100L)
      if (
        isTRUE(attr(rows, "truncated")) ||
          nrow(rows) != max(rows$revision_number)
      ) {
        artifact_error(
          "Cannot export incomplete or bounded-out native history."
        )
      }
      lapply(seq_len(nrow(rows)), function(i) {
        migration_plain(lapply(rows, \(column) column[[i]]))
      })
    }),
    recursive = FALSE
  )
  native <- list(initial = first, correction = corrected)
  checkpoints <- lapply(native, function(basis) {
    list(
      snapshot = migration_properties(basis$snapshot),
      selections = migration_plain(basis$selections),
      record_ids = as.list(basis$record_ids),
      revision_ids = as.list(basis$revision_ids),
      report_md = basis$report_md,
      resources = migration_resources(recipe$read_briefing_basis(store, basis))
    )
  })
  stopifnot(identical(original, checkpoints$initial$resources))
  final <- graft::graft_snapshot(store)
  stopifnot(isTRUE(final@history_complete))
  schema_path <- system.file(
    "schema/tempest-research.graft.json",
    package = "tempest"
  )
  export <- list(
    format = 1L,
    scope = "Tempest accepted-research fixture; one compiled schema; public record history",
    final_snapshot = migration_properties(final),
    schema = migration_plain(store@schema@manifest),
    schema_file_text = rawToChar(artifact_read_bytes(schema_path)),
    schema_file_sha256 = artifact_hash(artifact_read_bytes(schema_path)),
    promotion_bundles = stats::setNames(
      lapply(names(pins), function(day) {
        list(
          bundle_id = pins[[day]],
          bundle_json = rawToChar(artifact_read_bytes(file.path(
            fixture,
            day,
            "bundle.json"
          ))),
          manifest_json = rawToChar(artifact_read_bytes(file.path(
            fixture,
            day,
            "manifest.json"
          )))
        )
      }),
      names(pins)
    ),
    receipts = receipts,
    history = history,
    checkpoints = checkpoints,
    changes = migration_plain(recipe$briefing_changes(store, first)),
    unchanged = TRUE,
    unsupported = c(
      "Native Tempest knowledge admission from a manifest view",
      "Public deletion/tombstone production through Tempest",
      "Original external web bodies and executable ProgramArtifact payloads absent from these bundles",
      "Other schemas, sensitive fields, unselected store history, concurrent writes and production recovery"
    )
  )
  saveRDS(native, file.path(directory, "native-checkpoints.rds"))
  artifact_write(
    charToRaw(artifact_json(export)),
    file.path(directory, "export.json")
  )
  list(pid = Sys.getpid(), export = export)
}

migration_check_receipt <- function(store, receipt, snapshot) {
  S7::validate(receipt)
  view <- graft::graft_at(store, snapshot)
  actual <- migration_properties(graft::graft_view_snapshot(view))
  if (
    !identical(
      actual[names(receipt@snapshot)],
      migration_plain(receipt@snapshot)
    )
  ) {
    artifact_error(
      "Original receipt does not match its reopened native snapshot."
    )
  }
  for (ref in receipt@record_revisions) {
    history <- graft::graft_history(view, ref$record_id, limit = 1L)
    fields <- c(
      "record_id",
      "class",
      "revision_id",
      "revision_number",
      "batch_id",
      "schema_build_digest"
    )
    actual <- lapply(history[fields], \(column) column[[1L]])
    if (!identical(migration_plain(actual), migration_plain(ref[fields]))) {
      artifact_error(
        "Original receipt does not match its reopened native revision."
      )
    }
  }
  migration_properties(receipt)
}

migration_rollback <- function(directory) {
  store <- graft::graft_open(
    tempest::tempest_graft_schema(),
    file.path(directory, "source.duckdb"),
    read_only = TRUE,
    okf = "disabled"
  )
  on.exit(graft::graft_close(store), add = TRUE)
  # This is the trusted checkpoint created above, never an importer input.
  native <- readRDS(file.path(directory, "native-checkpoints.rds"))
  accepted <- readRDS(file.path(directory, "native-receipts.rds"))
  receipts <- Map(
    \(receipt, snapshot) migration_check_receipt(store, receipt, snapshot),
    accepted$receipts,
    accepted$snapshots
  )
  recipe <- migration_recipe()
  checkpoints <- lapply(names(native), function(name) {
    basis <- native[[name]]
    basis$selections <- list(recipe$briefing_selection(accepted$receipts[[
      name
    ]]))
    list(
      snapshot = migration_properties(basis$snapshot),
      resources = migration_resources(recipe$read_briefing_basis(store, basis)),
      report_md = basis$report_md
    )
  })
  list(
    receipts = receipts,
    checkpoints = stats::setNames(checkpoints, names(native))
  )
}
