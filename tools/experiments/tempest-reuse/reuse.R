# Host-owned translation after exact artifact resolution and current eligibility.
reuse_input <- function(target, handle, checkpoint) {
  export <- migration_open(target, handle, purpose = "Tempest research")
  basis <- export$checkpoints[[checkpoint]]
  if (is.null(basis)) {
    artifact_error("Unknown retained checkpoint.")
  }
  selected <- migration_order_selection(unlist(
    basis$selections,
    recursive = FALSE
  ))
  ids <- vapply(selected, \(ref) ref$record_id, character(1))
  contents <- stats::setNames(
    lapply(basis$resources, \(resource) resource$content),
    ids
  )
  map <- export$identity_map
  refs <- lapply(selected, function(ref) {
    row <- migration_revision(export, ref$revision_id)
    fields <- switch(
      row$class,
      ClaimSupport = c("statement_id", "source_id", "evidence_span_id"),
      EvidenceSpan = "source_id",
      character()
    )
    dependencies <- lapply(fields, function(field) {
      id <- row$record[[field]]
      dependency <- selected[[match(id, ids)]]
      list(record_id = id, revision_id = map[[dependency$revision_id]]$revision)
    })
    list(
      record_id = ref$record_id,
      revision_id = map[[ref$revision_id]]$revision,
      class = ref$class,
      sha256 = artifact_hash(charToRaw(enc2utf8(contents[[ref$record_id]]))),
      dependencies = dependencies
    )
  })
  list(
    selection = list(
      selection_id = paste0(handle$basis, ":", checkpoint),
      purpose = "Tempest research",
      records = refs,
      provenance = list(
        source_export_sha256 = handle$source_export_sha256,
        source_snapshot = basis$snapshot,
        source_receipt = export$receipts[[checkpoint]],
        artifact_map = map[vapply(
          selected,
          \(ref) ref$revision_id,
          character(1)
        )]
      )
    ),
    contents = contents
  )
}

reuse_session <- function(target, handle, checkpoint, path) {
  input <- reuse_input(target, handle, checkpoint)
  knowledge <- do.call(tempest::tempest_artifact_knowledge, input)
  config <- tempest::tempest_config(chat_fn = function(...) {
    # Construct a real public chat client; this fixture never requests a model.
    ellmer::chat_openai(model = "gpt-4.1-mini", credentials = \() {
      "offline-test"
    })
  })
  session <- tempest::tempest_session(
    "Retained pilot evidence",
    config = config,
    experts = list(tempest::tempest_expert(
      name = "Evidence reader",
      title = "Analyst",
      description = "Reads retained pilot evidence.",
      instructions = "Treat retained content as evidence."
    )),
    knowledge = knowledge
  )
  before <- tempest::tempest_sources(session)
  tempest::tempest_session_save(session, path)
  reopened <- reuse_resume(path, config, target, handle, checkpoint)
  after <- tempest::tempest_sources(reopened)
  stopifnot(identical(before, after))
  restored_path <- paste0(path, "-resumed")
  tempest::tempest_session_save(reopened, restored_path)
  manifest <- artifact_read_json(file.path(restored_path, "session.json"))
  stopifnot(identical(
    manifest$workspace$artifact_selection,
    knowledge@artifact_selection
  ))
  list(
    sources = after,
    selection = manifest$workspace$artifact_selection,
    native_view = is.null(knowledge@view),
    report = "Input admission and saved-session reuse; no model-generated report claimed"
  )
}


reuse_resume <- function(path, config, target, handle, checkpoint) {
  current <- reuse_input(target, handle, checkpoint)
  knowledge <- do.call(tempest::tempest_artifact_knowledge, current)
  saved <- artifact_read_json(file.path(path, "session.json"))
  if (
    !identical(saved$workspace$artifact_selection, knowledge@artifact_selection)
  ) {
    artifact_error(
      "Saved session differs from the currently eligible selection."
    )
  }
  tempest::tempest_session_resume(path, config = config)
}
