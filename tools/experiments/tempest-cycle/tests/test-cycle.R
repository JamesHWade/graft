test_that("both drivers accept, correct and withdraw research across processes", {
  results <- list()
  for (backend in c("manifest", "graft")) {
    root <- file.path(cycle_fixture$output, backend)
    staged <- cycle_run(
      backend,
      root,
      cycle_stage_in_child,
      "initial",
      cycle_stage_fixture
    )
    # Saving a completed proposal creates neither approval nor a usable session.
    head <- cycle_run(backend, root, cycle_head)
    expect_null(head$value)
    fabricated <- list(
      key = "fake",
      request_id = "fake",
      receipt = staged$value,
      eligible = TRUE
    )
    expect_error(
      cycle_run(backend, root, cycle_input, fabricated),
      "No recorded host acceptance",
      class = "callr_error"
    )
    initial <- cycle_run(
      backend,
      root,
      cycle_accept,
      staged$value,
      "review-1",
      NULL,
      "Reviewed original evidence"
    )
    saved <- cycle_run(
      backend,
      root,
      cycle_session,
      initial$value,
      file.path(root, "initial-session")
    )
    resumed <- cycle_run(
      backend,
      root,
      cycle_session,
      initial$value,
      file.path(root, "initial-session"),
      TRUE
    )
    expect_identical(resumed$value, saved$value)
    expect_length(
      unique(c(staged$pid, initial$pid, saved$pid, resumed$pid)),
      4L
    )
    expect_error(
      cycle_run(backend, root, cycle_input, initial$value, "Other purpose"),
      "not currently eligible",
      class = "callr_error"
    )
    expect_match(
      paste(saved$value$sources$content_text, collapse = "\n"),
      "82%",
      fixed = TRUE
    )
    expect_equal(nrow(saved$value$sources), 4L)
    unchanged <- cycle_run(
      backend,
      root,
      cycle_accept,
      staged$value,
      "review-2",
      initial$value,
      "Reviewed unchanged evidence"
    )
    same <- cycle_run(backend, root, cycle_input, unchanged$value)
    first <- cycle_run(backend, root, cycle_inspect, initial$value)
    expect_identical(
      same$value$selection$records,
      cycle_run(
        backend,
        root,
        function(store, event) {
          request <- cycle_inspect(store, event)
          lapply(request$staged$records, function(record) {
            item <- artifact_resolve(store, record$ref)
            list(
              record_id = record$record_id,
              revision_id = record$ref$revision,
              class = record$class,
              sha256 = item$metadata$payload,
              dependencies = lapply(item$metadata$dependencies, function(ref) {
                dep <- artifact_resolve(store, ref)
                list(
                  record_id = dep$metadata$meaning$record_id,
                  revision_id = ref$revision
                )
              })
            )
          })
        },
        initial$value
      )$value
    )
    expect_length(
      unique(c(initial$value$request_id, unchanged$value$request_id)),
      2L
    )
    expect_error(
      cycle_run(
        backend,
        root,
        cycle_session,
        initial$value,
        file.path(root, "initial-session"),
        TRUE
      ),
      "not currently eligible",
      class = "callr_error"
    )
    corrected_stage <- cycle_run(
      backend,
      root,
      cycle_stage_in_child,
      "correction",
      cycle_stage_fixture
    )
    # A saved correction has no authority until the host accepts it.
    expect_identical(
      cycle_run(backend, root, cycle_input, unchanged$value)$value,
      same$value
    )
    expect_error(
      cycle_run(
        backend,
        root,
        cycle_accept,
        corrected_stage$value,
        "stale",
        initial$value,
        "Correction"
      ),
      "Acceptance changed",
      class = "callr_error"
    )
    corrected <- cycle_run(
      backend,
      root,
      cycle_accept,
      corrected_stage$value,
      "review-3",
      unchanged$value,
      "Correct 82% to 62%"
    )
    current <- cycle_run(
      backend,
      root,
      cycle_session,
      corrected$value,
      file.path(root, "corrected-session")
    )
    expect_match(
      paste(current$value$sources$content_text, collapse = "\n"),
      "62%",
      fixed = TRUE
    )
    expect_error(
      cycle_run(backend, root, cycle_input, unchanged$value),
      "not currently eligible",
      class = "callr_error"
    )
    expect_error(
      cycle_run(
        backend,
        root,
        cycle_session,
        corrected$value,
        file.path(root, "initial-session"),
        TRUE
      ),
      "differs from the eligible acceptance",
      class = "callr_error"
    )
    expect_identical(
      cycle_run(backend, root, cycle_inspect, initial$value)$value,
      first$value
    )
    history <- cycle_run(
      backend,
      root,
      function(store, event) {
        request <- cycle_inspect(store, event)
        lapply(artifact_closure(store, list(event$receipt)), function(ref) {
          artifact_resolve(store, ref)$bytes
        })
      },
      corrected$value
    )
    withdrawn <- cycle_run(
      backend,
      root,
      cycle_withdraw,
      corrected$value,
      "Host withdrew the conclusion"
    )
    expect_identical(withdrawn$value$eligible, FALSE)
    expect_error(
      cycle_run(backend, root, cycle_input, corrected$value),
      "not currently eligible",
      class = "callr_error"
    )
    expect_error(
      cycle_run(
        backend,
        root,
        cycle_session,
        corrected$value,
        file.path(root, "corrected-session"),
        TRUE
      ),
      "not currently eligible",
      class = "callr_error"
    )
    retry <- cycle_run(
      backend,
      root,
      cycle_accept,
      corrected_stage$value,
      "review-3",
      unchanged$value,
      "Correct 82% to 62%"
    )
    expect_identical(retry$value, corrected$value)
    expect_identical(
      cycle_run(backend, root, cycle_head)$value,
      withdrawn$value
    )
    expect_error(
      cycle_run(
        backend,
        root,
        cycle_accept,
        corrected_stage$value,
        "review-3",
        unchanged$value,
        "Changed reason"
      ),
      "key reused",
      class = "callr_error"
    )
    retained <- cycle_run(
      backend,
      root,
      function(store, event) {
        request <- cycle_inspect(store, event)
        lapply(artifact_closure(store, list(event$receipt)), function(ref) {
          artifact_resolve(store, ref)$bytes
        })
      },
      corrected$value
    )
    expect_identical(retained$value, history$value)
    # Compare every accepted record to the independently pinned public fixture.
    for (case in c("initial", "correction")) {
      event <- if (case == "initial") initial$value else corrected$value
      actual <- cycle_run(
        backend,
        root,
        function(store, event) {
          request <- cycle_inspect(store, event)
          list(
            records = lapply(request$staged$records, function(record) {
              list(
                class = record$class,
                value = jsonlite::fromJSON(
                  rawToChar(artifact_resolve(store, record$ref)$bytes),
                  simplifyVector = FALSE
                )
              )
            }),
            saved = lapply(request$staged$saved, function(ref) {
              artifact_resolve(store, ref)$bytes
            })
          )
        },
        event
      )$value
      fixture <- system.file("examples/accepted-research", package = "tempest")
      expected <- artifact_read_json(file.path(fixture, case, "bundle.json"))
      expect_identical(
        lapply(actual$records, function(x) x$value$record),
        unname(unlist(
          expected$records[c(
            "Source",
            "Claim",
            "EvidenceSpan",
            "ClaimSupport"
          )],
          recursive = FALSE
        ))
      )
      expect_identical(
        actual$records[[1L]]$value$resource,
        expected$proof$resources[[1L]]
      )
      expect_identical(
        actual$saved$bundle.json,
        artifact_read_bytes(file.path(fixture, case, "bundle.json"))
      )
      expect_identical(
        actual$saved$manifest.json,
        artifact_read_bytes(file.path(fixture, case, "manifest.json"))
      )
      expect_identical(
        actual$saved$report,
        artifact_read_bytes(file.path(fixture, paste0(case, "-report.md")))
      )
    }
    if (backend == "manifest") {
      expect_identical(staged$graft_available, FALSE)
      expect_identical(initial$graft_available, FALSE)
      expect_identical(resumed$graft_available, FALSE)
      expect_identical(corrected$graft_available, FALSE)
      expect_identical(withdrawn$graft_available, FALSE)
    }
    results[[backend]] <- list(
      initial = initial$value,
      unchanged = unchanged$value,
      corrected = corrected$value,
      withdrawn = withdrawn$value,
      retained = retained$value
    )
  }
  expect_identical(results$manifest, results$graft)
  cycle_fixture$observed$lifecycle <- list(
    backends = names(results),
    exact_parity = TRUE,
    manifest_acceptance_without_graft = TRUE,
    retry_does_not_reapprove = TRUE,
    independent_processes = TRUE,
    retained_history_after_withdrawal = TRUE
  )
})
