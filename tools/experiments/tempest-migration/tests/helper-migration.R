migration_checkout <- getOption("graft.experiment.checkout")
for (file in c(
  "artifacts/content.R",
  "artifacts/backends.R",
  "tempest-migration/migration.R",
  "tempest-migration/producer.R"
)) {
  sys.source(
    file.path(migration_checkout, "tools/experiments", file),
    environment()
  )
}
migration_fixture_path <- getOption("graft.migration.fixture")
migration_fixture <- artifact_read_json(migration_fixture_path)
migration_fixture_digest <- artifact_hash(artifact_read_bytes(
  migration_fixture_path
))

local_migration <- function(.local_envir = parent.frame()) {
  target <- withr::local_tempdir(.local_envir = .local_envir)
  handle <- migration_import(
    migration_fixture_path,
    migration_fixture_digest,
    target
  )
  list(target = target, handle = handle)
}
