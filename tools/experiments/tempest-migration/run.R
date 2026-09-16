source("tools/experiments/runtime.R")
experiment_prepare()
checkout <- normalizePath(".")
source("tools/experiments/artifacts/content.R")
source("tools/experiments/artifacts/backends.R")
source("tools/experiments/tempest-migration/migration.R")
output <- file.path(
  Sys.getenv("GRAFT_EXPERIMENT_OUTPUT", tempfile("migration-evidence-")),
  "tempest-migration"
)
dir.create(output, recursive = TRUE, showWarnings = FALSE)
source_path <- tempfile("native-source-", tmpdir = output)
native <- function(action) {
  callr::r(
    function(checkout, source_path, action) {
      source(file.path(checkout, "tools/experiments/artifacts/content.R"))
      source(file.path(
        checkout,
        "tools/experiments/tempest-migration/producer.R"
      ))
      if (action == "produce") {
        migration_produce(source_path)
      } else {
        migration_rollback(source_path)
      }
    },
    args = list(checkout, source_path, action),
    libpath = .libPaths()
  )
}
produced <- native("produce")
source_digest <- experiment_tree_digest(source_path)
target_path <- tempfile("manifest-target-", tmpdir = output)
export_path <- file.path(source_path, "export.json")
export_digest <- artifact_hash(artifact_read_bytes(export_path))
handle <- migration_import(export_path, export_digest, target_path)
artifact_write(
  charToRaw(artifact_json(list(
    target = basename(target_path),
    handle = handle
  ))),
  file.path(output, "handoff.json")
)
stopifnot(identical(
  migration_open(target_path, handle)$checkpoints,
  produced$export$checkpoints
))
options(
  graft.experiment.checkout = checkout,
  graft.migration.fixture = file.path(source_path, "export.json")
)
tests <- testthat::test_dir(
  "tools/experiments/tempest-migration/tests",
  stop_on_failure = TRUE
)
rollback <- native("rollback")
stopifnot(identical(experiment_tree_digest(source_path), source_digest))
for (name in names(rollback)) {
  expected <- produced$export$checkpoints[[name]]
  stopifnot(identical(
    rollback[[name]],
    expected[c("snapshot", "resources", "report_md")]
  ))
}
result <- list(
  outcome = "Historical export/read parity; native Tempest admission requires a new public seam",
  recommendation = "reduce; retain Graft for the existing Tempest contract",
  assertions = sum(as.data.frame(tests)$passed),
  native_history_revisions = length(produced$export$history),
  retained_receipts = length(produced$export$receipts),
  retained_target_artifacts = length(artifact_all_current(artifact_store(
    target_path,
    "manifest",
    "unused"
  ))),
  evidence_per_checkpoint = lapply(produced$export$checkpoints, \(basis) {
    length(basis$resources)
  }),
  source_unchanged = TRUE,
  rollback_verified = TRUE,
  source_export_sha256 = export_digest,
  packages = jsonlite::read_json("tools/experiments/pins.json")$packages,
  unsupported = produced$export$unsupported
)
jsonlite::write_json(
  result,
  file.path(output, "results.json"),
  pretty = TRUE,
  auto_unbox = TRUE
)
cat("Tempest migration experiment passed. Evidence:", output, "\n")
