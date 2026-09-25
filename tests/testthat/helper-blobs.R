local_artifact_store <- function(env = parent.frame()) {
  directory <- withr::local_tempdir(.local_envir = env)
  schema <- graft_schema(system.file(
    "extdata",
    "artifacts.data-dict.json",
    package = "graft",
    mustWork = TRUE
  ))
  store <- graft_open(
    schema,
    file.path(directory, "project.duckdb"),
    okf = "disabled"
  )
  withr::defer(graft_close(store), envir = env)
  store
}

tiny_png <- function() {
  as.raw(c(
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
    0x00,
    0x00,
    0x00,
    0x0d,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1f,
    0x15,
    0xc4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0d,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9c,
    0x63,
    0xf8,
    0xcf,
    0xc0,
    0xf0,
    0x1f,
    0x00,
    0x05,
    0x00,
    0x01,
    0xff,
    0x89,
    0x99,
    0x3d,
    0x1d,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4e,
    0x44,
    0xae,
    0x42,
    0x60,
    0x82
  ))
}

kept_artifact_records <- function(blob, title = "Cure conversion") {
  kept_at <- as.POSIXct("2026-09-24 12:00:00", tz = "UTC")
  list(
    graft_blob = blob,
    artifact = data.frame(
      id = "artifact:cure:conv-7:card-12",
      project_id = "cure",
      title = title,
      kind = "result",
      tool = "run_r_code",
      conversation_id = "conv-7",
      kept_by = "scientist",
      kept_at = kept_at
    ),
    artifact_provenance = data.frame(
      id = "provenance:conv-7:card-12:v1",
      producer = "run_r_code",
      runtime = "r",
      package = "ggplot2",
      package_version = "3.5.2",
      capture = "exact",
      code = "plot(runs)",
      conversation_id = "conv-7",
      tool_call_id = "call_1",
      recorded_at = kept_at
    ),
    artifact_version = data.frame(
      id = "artifact:cure:conv-7:card-12:v1",
      artifact_id = "artifact:cure:conv-7:card-12",
      version = 1,
      blob_id = blob$id,
      text = "Conversion by protocol.",
      provenance_id = "provenance:conv-7:card-12:v1"
    )
  )
}

blob_test_provenance <- function(key = "keep-1") {
  graft_provenance(producer = "crucible", idempotency_key = key)
}
