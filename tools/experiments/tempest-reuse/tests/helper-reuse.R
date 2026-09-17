checkout <- getOption("graft.experiment.checkout")
for (file in c(
  "artifacts/content.R",
  "artifacts/backends.R",
  "tempest-migration/migration.R",
  "tempest-reuse/reuse.R"
)) {
  source(file.path(checkout, "tools/experiments", file))
}
reuse_fixture <- getOption("graft.reuse.fixture")
