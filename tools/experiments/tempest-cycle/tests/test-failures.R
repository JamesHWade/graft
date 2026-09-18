test_that("rejected proposals and interrupted acceptance never authorize reuse", {
  for (backend in c("manifest", "graft")) {
    root <- file.path(cycle_fixture$output, paste0(backend, "-failures"))
    result <- cycle_run(
      backend,
      root,
      function(store, stage) {
        fixture <- system.file(
          "examples/accepted-research",
          package = "tempest"
        )
        pin <- "sha256:00e1323021683893220b0b919ce019933449d97d01a0da1e0ece858964cb1c86"
        error_text <- function(expr) {
          tryCatch(
            {
              force(expr)
              "unexpected success"
            },
            error = conditionMessage
          )
        }
        altered_report <- tempfile()
        writeLines("Unreviewed result", altered_report)
        bad_report <- error_text(cycle_stage(
          store,
          file.path(fixture, "initial"),
          pin,
          altered_report
        ))
        wrong_pin <- error_text(cycle_stage(
          store,
          file.path(fixture, "correction"),
          pin,
          file.path(fixture, "correction-report.md")
        ))
        staged <- stage(store, "initial")
        bad_purposes <- lapply(
          list(
            "",
            NULL,
            NA_character_,
            123,
            c("one", "two"),
            "   ",
            " Tempest research "
          ),
          function(purpose) {
            error_text(cycle_accept(
              store,
              staged,
              "invalid-purpose",
              NULL,
              "Reviewed",
              purpose
            ))
          }
        )
        empty_after_bad_purposes <- is.null(cycle_head(store))
        candidate <- cycle_candidate(store, staged)
        report <- artifact_resolve(store, candidate$saved$report)
        path <- artifact_digest_path(
          store$root,
          "content",
          report$metadata$payload
        )
        writeBin(charToRaw("tampered"), path)
        corrupt <- error_text(cycle_accept(
          store,
          staged,
          "review",
          NULL,
          "Reviewed"
        ))
        empty_after_corrupt <- is.null(cycle_head(store))
        writeBin(report$bytes, path)
        # Interrupt the host's final publication, after the immutable receipt exists.
        real_rename <- artifact_rename
        assign(
          "artifact_rename",
          function(from, to) {
            if (basename(to) == "acceptance.json") {
              FALSE
            } else {
              real_rename(from, to)
            }
          },
          envir = globalenv()
        )
        interrupted <- error_text(cycle_accept(
          store,
          staged,
          "review",
          NULL,
          "Reviewed"
        ))
        empty_after_interrupt <- is.null(cycle_head(store))
        assign("artifact_rename", real_rename, envir = globalenv())
        accepted <- cycle_accept(store, staged, "review", NULL, "Reviewed")
        input <- cycle_input(store, accepted)
        # Once approved, corruption must also stop a fresh consultation.
        writeBin(charToRaw("tampered"), path)
        corrupt_after <- error_text(cycle_input(store, accepted))
        writeBin(report$bytes, path)
        list(
          bad_report = bad_report,
          bad_purposes = bad_purposes,
          empty_after_bad_purposes = empty_after_bad_purposes,
          wrong_pin = wrong_pin,
          corrupt = corrupt,
          empty_after_corrupt = empty_after_corrupt,
          interrupted = interrupted,
          empty_after_interrupt = empty_after_interrupt,
          corrupt_after = corrupt_after,
          accepted = accepted,
          retried = cycle_accept(store, staged, "review", NULL, "Reviewed"),
          count = length(cycle_journal(store)),
          input = input
        )
      },
      cycle_stage_fixture
    )$value
    for (message in result$bad_purposes) {
      expect_match(
        message,
        "Acceptance requires one nonempty, unpadded reuse purpose",
        fixed = TRUE
      )
    }
    expect_identical(result$empty_after_bad_purposes, TRUE)
    expect_match(result$bad_report, "Report differs", fixed = TRUE)
    expect_match(result$wrong_pin, "trusted bundle id", fixed = TRUE)
    expect_match(
      result$corrupt,
      "Content digest or size mismatch",
      fixed = TRUE
    )
    expect_identical(result$empty_after_corrupt, TRUE)
    expect_match(result$interrupted, "Publication failed", fixed = TRUE)
    expect_identical(result$empty_after_interrupt, TRUE)
    expect_identical(result$accepted, result$retried)
    expect_equal(result$count, 1L)
    expect_length(result$input$selection$records, 4L)
    expect_match(
      result$corrupt_after,
      "Content digest or size mismatch",
      fixed = TRUE
    )
  }
  cycle_fixture$observed$failure_checks <- list(
    reject_wrong_bundle_and_report = TRUE,
    reject_changed_bytes = TRUE,
    interrupted_approval_retry = TRUE
  )
})
