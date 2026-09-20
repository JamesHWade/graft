artifact_recovery_ref_key <- function(ref) {
  paste(ref$id, ref$revision, sep = "\n")
}

artifact_recovery_object_key <- function(object) {
  paste(object$kind, object$key, sep = "\n")
}

artifact_recovery_manifest_keys <- function(manifest) {
  vapply(manifest$objects, artifact_recovery_object_key, character(1))
}

artifact_recovery_ref_keys <- function(refs) {
  vapply(refs, artifact_recovery_ref_key, character(1))
}

artifact_recovery_removed_ref_keys <- function(plan) {
  artifact_recovery_ref_keys(plan$removed$artifacts)
}

artifact_recovery_fixture <- function(store) {
  shared <- artifact_save(
    store,
    "shared",
    charToRaw("shared bytes"),
    "text/plain"
  )
  forgotten <- artifact_save(
    store,
    "forgotten",
    charToRaw("shared bytes"),
    "text/plain"
  )
  leaf <- artifact_save(
    store,
    "leaf",
    charToRaw("leaf bytes"),
    "text/plain"
  )
  dependent <- artifact_save(
    store,
    "dependent",
    charToRaw("dependent bytes"),
    "text/plain",
    dependencies = list(leaf)
  )
  survivor <- artifact_save(
    store,
    "survivor",
    charToRaw("survivor bytes"),
    "text/plain"
  )
  removed_selection <- artifact_select(store, list(dependent))
  retained_selection <- artifact_select(
    store,
    list(survivor, shared)
  )
  removed_decision <- artifact_decide(
    store,
    "removed-stream",
    "accept-1",
    NULL,
    removed_selection,
    "accept",
    "reviewer",
    "remove",
    "research"
  )
  mixed_first <- artifact_decide(
    store,
    "mixed-stream",
    "accept-1",
    NULL,
    removed_selection,
    "accept",
    "reviewer",
    "first basis",
    "research"
  )
  mixed_second <- artifact_decide(
    store,
    "mixed-stream",
    "accept-2",
    mixed_first$id,
    retained_selection,
    "accept",
    "reviewer",
    "corrected basis",
    "research"
  )
  explicit_decision <- artifact_decide(
    store,
    "explicit-stream",
    "accept-1",
    NULL,
    retained_selection,
    "accept",
    "reviewer",
    "explicit stream",
    "research"
  )
  retained_decision <- artifact_decide(
    store,
    "retained-stream",
    "accept-1",
    NULL,
    retained_selection,
    "accept",
    "reviewer",
    "retained stream",
    "research"
  )
  list(
    shared = shared,
    forgotten = forgotten,
    leaf = leaf,
    dependent = dependent,
    survivor = survivor,
    removed_selection = removed_selection,
    retained_selection = retained_selection,
    removed_decision = removed_decision,
    mixed_first = mixed_first,
    mixed_second = mixed_second,
    explicit_decision = explicit_decision,
    retained_decision = retained_decision
  )
}

artifact_recovery_plan <- function(store, fixture) {
  graft_plan_replacement(
    store,
    forget = list(fixture$leaf, fixture$forgotten),
    forget_streams = "explicit-stream"
  )
}

artifact_recovery_synthetic_write_journal <- function(path, journal) {
  saveRDS(journal, path, version = 3)
  invisible(NULL)
}

artifact_recovery_synthetic_read_journal <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }
  tryCatch(readRDS(path), error = function(error) NULL)
}

artifact_recovery_synthetic_admit <- function(
  path,
  generation,
  ref,
  store = NULL,
  expected_reader = NULL
) {
  unavailable <- function(reason) {
    list(admitted = FALSE, reason = reason)
  }
  journal <- artifact_recovery_synthetic_read_journal(path)
  if (is.null(journal)) {
    return(unavailable("missing-journal"))
  }
  if (
    !is.list(journal) ||
      !identical(journal$format, "synthetic-host-journal/1")
  ) {
    return(unavailable("invalid-journal"))
  }
  if (
    !is.null(expected_reader) &&
      !identical(journal$reader, expected_reader)
  ) {
    return(unavailable("reader-mismatch"))
  }
  if (generation %in% journal$retired_generations) {
    return(unavailable("generation-retired"))
  }
  published <- journal$published
  if (
    !is.list(published) ||
      !identical(published$generation, generation)
  ) {
    return(unavailable("generation-unpublished"))
  }
  if (is.null(store) || is.null(expected_reader)) {
    return(unavailable("missing-binding"))
  }
  if (!is.null(store)) {
    manifest <- tryCatch(
      graft_manifest(store),
      error = function(error) NULL
    )
    if (
      is.null(manifest) ||
        !identical(manifest$id, published$manifest)
    ) {
      return(unavailable("manifest-mismatch"))
    }
  }
  if (!artifact_recovery_ref_key(ref) %in% published$refs) {
    return(unavailable("reference-unpublished"))
  }
  list(admitted = TRUE, generation = generation, ref = ref)
}
