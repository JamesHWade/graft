# Experiment-only host: trusted files, one writer, one research topic.
cycle_load <- function(checkout, envir) {
  for (file in c("artifacts/content.R", "artifacts/backends.R")) {
    sys.source(file.path(checkout, "tools/experiments", file), envir)
  }
}

cycle_journal <- function(store) {
  path <- file.path(store$root, "acceptance.json")
  if (file.exists(path)) artifact_read_json(path) else list()
}

cycle_head <- function(store) {
  events <- cycle_journal(store)
  if (length(events)) events[[length(events)]] else NULL
}

cycle_append <- function(store, event, expected) {
  if (!identical(cycle_head(store), expected)) {
    artifact_error("Acceptance changed; review the current decision.")
  }
  events <- cycle_journal(store)
  if (length(events) >= 100L) {
    artifact_error("Acceptance journal exceeds bound.")
  }
  artifact_write(
    charToRaw(artifact_json(c(events, list(event)))),
    file.path(store$root, "acceptance.json"),
    replace = TRUE
  )
  event
}

cycle_save <- function(
  store,
  id,
  bytes,
  dependencies = list(),
  meaning = list(),
  media_type = "application/json"
) {
  path <- tempfile()
  on.exit(unlink(path))
  writeBin(bytes, path)
  artifact_save(
    store,
    id,
    path,
    media_type,
    dependencies,
    meaning,
    producer = "tempest-cycle-host:v1"
  )
}

cycle_record_id <- function(class, row) {
  field <- switch(
    class,
    Source = "tempest_source_id",
    Claim = "tempest_claim_id",
    EvidenceSpan = "id",
    ClaimSupport = "tempest_claim_support_id"
  )
  row[[field]]
}

cycle_record_key <- function(class, id) paste(class, id, sep = ":")

cycle_stage <- function(store, path, bundle_id, report) {
  # This public reader validates the proposal and evidence against an independent pin.
  bundle <- tempest::tempest_read_promotion_bundle(path, bundle_id)
  report_bytes <- artifact_read_bytes(report)
  # Shipped fixtures use writeLines(): one final LF wraps the product string.
  # Tempest hashes the JSON string; retain the file bytes separately and exactly.
  report_text <- sub("\\n$", "", rawToChar(report_bytes))
  if (
    !identical(
      paste0("sha256:", artifact_hash(charToRaw(artifact_json(report_text)))),
      bundle@research_manifest$deliverables$report_md$sha256
    )
  ) {
    artifact_error("Report differs from the completed research deliverable.")
  }
  saved <- list()
  for (file in c("bundle.json", "manifest.json")) {
    bytes <- artifact_read_bytes(file.path(path, file))
    saved[[file]] <- cycle_save(
      store,
      paste0("artifact:bundle-", artifact_hash(bytes)),
      bytes
    )
  }
  saved$report <- cycle_save(
    store,
    paste0("artifact:report-", artifact_hash(report_bytes)),
    report_bytes,
    media_type = "text/markdown"
  )
  refs <- list()
  records <- list()
  for (class in c("Source", "Claim", "EvidenceSpan", "ClaimSupport")) {
    for (row in bundle@records[[class]]) {
      id <- cycle_record_id(class, row)
      key <- cycle_record_key(class, id)
      fields <- switch(
        class,
        EvidenceSpan = c(source_id = "Source"),
        ClaimSupport = c(
          statement_id = "Claim",
          source_id = "Source",
          evidence_span_id = "EvidenceSpan"
        ),
        character()
      )
      dependencies <- lapply(names(fields), function(field) {
        ref <- refs[[cycle_record_key(fields[[field]], row[[field]])]]
        if (is.null(ref)) {
          artifact_error(
            "Proposal dependency is outside the accepted evidence."
          )
        }
        ref
      })
      value <- list(record = row)
      if (class == "Source") {
        resource <- Filter(
          function(x) identical(x$resource_id, id),
          bundle@proof$resources
        )
        if (length(resource) != 1L) {
          artifact_error("Source body is missing or ambiguous.")
        }
        value$resource <- resource[[1L]]
      }
      ref <- cycle_save(
        store,
        paste0("artifact:record-", artifact_hash(charToRaw(key))),
        charToRaw(artifact_json(value)),
        dependencies,
        list(class = class, record_id = key)
      )
      refs[[key]] <- ref
      records[[length(records) + 1L]] <- list(
        record_id = key,
        class = class,
        ref = ref
      )
    }
  }
  candidate <- list(
    bundle_id = bundle_id,
    research_run_id = bundle@research_run_id,
    saved = saved,
    records = records,
    roots = unname(c(saved, refs))
  )
  bytes <- charToRaw(artifact_json(candidate))
  cycle_save(
    store,
    paste0("artifact:candidate-", artifact_hash(bytes)),
    bytes,
    candidate$roots,
    list(kind = "tempest-proposal")
  )
}

cycle_candidate <- function(store, ref) {
  item <- artifact_resolve(store, ref)
  if (!identical(item$metadata$meaning, list(kind = "tempest-proposal"))) {
    artifact_error("Acceptance requires a staged Tempest proposal.")
  }
  candidate <- jsonlite::fromJSON(rawToChar(item$bytes), simplifyVector = FALSE)
  if (!identical(candidate$roots, item$metadata$dependencies)) {
    artifact_error("Proposal dependencies differ from its retained selection.")
  }
  artifact_closure(store, list(ref))
  candidate
}

cycle_accept <- function(
  store,
  staged,
  key,
  expected,
  reason,
  purpose = "Tempest research"
) {
  if (
    !is.character(key) ||
      length(key) != 1L ||
      is.na(key) ||
      !nzchar(key) ||
      !is.character(reason) ||
      length(reason) != 1L ||
      is.na(reason) ||
      !nzchar(reason)
  ) {
    artifact_error(
      "Acceptance requires an explicit host key and review reason."
    )
  }
  request <- list(
    key = key,
    staged = staged,
    previous = expected,
    reason = reason,
    purpose = purpose
  )
  request_id <- artifact_hash(charToRaw(artifact_json(request)))
  previous <- Filter(
    function(event) identical(event$key, key),
    cycle_journal(store)
  )
  if (length(previous)) {
    event <- previous[[1L]]
    if (!identical(event$request_id, request_id)) {
      artifact_error("Acceptance key reused for a different decision.")
    }
    cycle_inspect(store, event)
    return(event) # A retry returns history; it never changes current eligibility.
  }
  if (!identical(cycle_head(store), expected)) {
    artifact_error("Acceptance changed; review the current decision.")
  }
  cycle_candidate(store, staged)
  receipt <- cycle_save(
    store,
    paste0("artifact:acceptance-", request_id),
    charToRaw(artifact_json(request)),
    list(staged)
  )
  cycle_append(
    store,
    list(
      key = key,
      request_id = request_id,
      receipt = receipt,
      eligible = TRUE
    ),
    expected
  )
}

cycle_inspect <- function(store, event) {
  if (
    !any(vapply(
      cycle_journal(store),
      function(accepted) identical(accepted, event),
      logical(1)
    ))
  ) {
    artifact_error("No recorded host acceptance for this selection.")
  }
  item <- artifact_resolve(store, event$receipt)
  if (!identical(artifact_hash(item$bytes), event$request_id)) {
    artifact_error("Acceptance receipt digest mismatch.")
  }
  request <- jsonlite::fromJSON(rawToChar(item$bytes), simplifyVector = FALSE)
  if (!identical(item$metadata$dependencies, list(request$staged))) {
    artifact_error("Receipt dependencies differ from the accepted selection.")
  }
  artifact_closure(store, list(event$receipt))
  request$staged <- cycle_candidate(store, request$staged)
  request
}

cycle_input <- function(store, event, purpose = "Tempest research") {
  request <- cycle_inspect(store, event)
  if (
    !identical(event, cycle_head(store)) ||
      !isTRUE(event$eligible) ||
      !identical(request$purpose, purpose)
  ) {
    artifact_error("Accepted selection is not currently eligible for this use.")
  }
  records <- request$staged$records
  contents <- list()
  refs <- lapply(records, function(record) {
    item <- artifact_resolve(store, record$ref)
    contents[[record$record_id]] <<- rawToChar(item$bytes)
    dependencies <- lapply(item$metadata$dependencies, function(ref) {
      dep <- artifact_resolve(store, ref)
      list(
        record_id = dep$metadata$meaning$record_id,
        revision_id = ref$revision
      )
    })
    list(
      record_id = record$record_id,
      revision_id = record$ref$revision,
      class = record$class,
      sha256 = item$metadata$payload,
      dependencies = dependencies
    )
  })
  list(
    selection = list(
      selection_id = event$request_id,
      purpose = purpose,
      records = refs,
      provenance = list(
        acceptance = event,
        bundle_id = request$staged$bundle_id,
        research_run_id = request$staged$research_run_id
      )
    ),
    contents = contents
  )
}

cycle_withdraw <- function(store, event, reason) {
  cycle_inspect(store, event)
  if (!identical(cycle_head(store), event) || !isTRUE(event$eligible)) {
    artifact_error("Only the current acceptance can be withdrawn.")
  }
  if (
    !is.character(reason) ||
      length(reason) != 1L ||
      is.na(reason) ||
      !nzchar(reason)
  ) {
    artifact_error("Withdrawal requires a reason.")
  }
  cycle_append(
    store,
    list(withdraws = event$request_id, reason = reason, eligible = FALSE),
    event
  )
}

cycle_session <- function(store, event, path, resume = FALSE) {
  input <- cycle_input(store, event)
  knowledge <- do.call(tempest::tempest_artifact_knowledge, input)
  if (resume) {
    saved <- artifact_read_json(file.path(path, "session.json"))
    if (
      !identical(
        saved$workspace$artifact_selection,
        knowledge@artifact_selection
      )
    ) {
      artifact_error("Saved session differs from the eligible acceptance.")
    }
    session <- tempest::tempest_session_resume(path, config = cycle_config())
    path <- paste0(path, "-resumed")
  } else {
    session <- tempest::tempest_session(
      "Accepted research",
      config = cycle_config(),
      experts = list(tempest::tempest_expert(
        name = "Reader",
        title = "Analyst",
        description = "Reads retained research",
        instructions = "Use the evidence."
      )),
      knowledge = knowledge
    )
  }
  tempest::tempest_session_save(session, path)
  list(
    sources = tempest::tempest_sources(session),
    selection = artifact_read_json(file.path(
      path,
      "session.json"
    ))$workspace$artifact_selection
  )
}

cycle_config <- function() {
  tempest::tempest_config(chat_fn = function(...) {
    ellmer::chat_openai(model = "gpt-4.1-mini", credentials = \() {
      "offline-test"
    })
  })
}
