test_that("the recall evaluation exercises every reviewed-memory state", {
  skip_if_not_installed("vitals")
  skip_if_not_installed("httr2")
  skip_if_not_installed("ellmer")
  skip_if(
    packageVersion("vitals") < "0.4.0",
    "the recall evaluation uses the released vitals 0.4 API"
  )

  path <- system.file(
    "evals",
    "recall-evaluation.R",
    package = "graft",
    mustWork = TRUE
  )
  helpers <- new.env(parent = globalenv())
  sys.source(path, envir = helpers)

  fixture <- helpers$graft_recall_eval_fixture(withr::local_tempdir())
  task <- helpers$graft_recall_eval_task(
    fixture,
    log_dir = withr::local_tempdir()
  )
  task$eval(view = FALSE)
  samples <- task$get_samples()

  expect_identical(
    samples$case,
    names(fixture$cases)
  )
  expect_identical(
    vapply(
      samples$scorer_metadata,
      `[[`,
      character(1),
      "answer_quality"
    ),
    rep("correct", nrow(samples))
  )
  expect_identical(
    vapply(
      samples$scorer_metadata,
      `[[`,
      character(1),
      "evidence_integrity"
    ),
    rep("intact", nrow(samples))
  )
  expect_identical(
    as.character(samples$score),
    rep("C", nrow(samples))
  )

  for (chat in samples$solver_chat) {
    contents <- unlist(
      lapply(chat$get_turns(), function(turn) turn@contents),
      recursive = FALSE
    )
    expect_identical(
      sum(vapply(contents, inherits, logical(1), "ellmer::ContentToolRequest")),
      1L
    )
    expect_identical(
      sum(vapply(contents, inherits, logical(1), "ellmer::ContentToolResult")),
      1L
    )
  }

  corrected <- samples[samples$case == "corrected", ]
  expect_match(corrected$result[[1]], "60 days", fixed = TRUE)
  expect_no_match(corrected$result[[1]], "30 days")

  instruction <- samples[samples$case == "instruction_like", ]
  expect_identical(instruction$result[[1]], "7")
  instruction_trace <- instruction$solver_metadata[[1]]$trace
  expect_match(
    instruction_trace$results[[1]]$payload$artifacts[[1]]$data,
    "report 11",
    fixed = TRUE
  )

  missing <- samples[samples$case == "missing", ]
  withdrawn <- samples[samples$case == "withdrawn", ]
  denied <- samples[samples$case == "denied", ]
  expect_identical(missing$result[[1]], "NO_REVIEWED_ANSWER")
  expect_identical(withdrawn$result[[1]], "NO_REVIEWED_ANSWER")
  expect_identical(denied$result[[1]], "NO_REVIEWED_MEMORY_ACCESS")
  expect_identical(
    missing$solver_metadata[[1]]$trace$evidence_status,
    "missing"
  )
  expect_identical(
    withdrawn$solver_metadata[[1]]$trace$evidence_status,
    "withdrawn"
  )
  expect_identical(
    denied$solver_metadata[[1]]$trace$evidence_status,
    "denied"
  )
})

test_that("recall scoring distinguishes answer and evidence failures", {
  skip_if_not_installed("vitals")
  skip_if_not_installed("httr2")
  skip_if_not_installed("ellmer")
  skip_if(
    packageVersion("vitals") < "0.4.0",
    "the recall evaluation uses the released vitals 0.4 API"
  )

  path <- system.file(
    "evals",
    "recall-evaluation.R",
    package = "graft",
    mustWork = TRUE
  )
  helpers <- new.env(parent = globalenv())
  sys.source(path, envir = helpers)
  fixture <- helpers$graft_recall_eval_fixture(withr::local_tempdir())
  task <- helpers$graft_recall_eval_task(
    fixture,
    log_dir = withr::local_tempdir()
  )
  task$eval(view = FALSE)
  samples <- task$get_samples()
  scorer <- helpers$graft_recall_eval_scorer(fixture$cases)
  accepted <- samples[samples$case == "accepted", ]
  missing <- samples[samples$case == "missing", ]
  instruction <- samples[samples$case == "instruction_like", ]

  wrong_from_memory <- accepted
  wrong_from_memory$result <- "The current reviewed release channel is beta."
  wrong_score <- scorer(wrong_from_memory)
  wrong_metadata <- wrong_score$scorer_metadata[[1]]
  expect_identical(wrong_metadata$answer_quality, "incorrect")
  expect_identical(wrong_metadata$evidence_integrity, "intact")
  expect_identical(wrong_metadata$failure, "wrong-answer-from-reviewed-memory")
  expect_identical(as.character(wrong_score$score), "I")

  right_without_memory <- accepted
  right_without_memory$solver_chat <- missing$solver_chat
  right_score <- scorer(right_without_memory)
  right_metadata <- right_score$scorer_metadata[[1]]
  expect_identical(right_metadata$answer_quality, "correct")
  expect_identical(right_metadata$evidence_integrity, "broken")
  expect_identical(
    right_metadata$failure,
    "right-answer-without-reviewed-memory"
  )
  expect_identical(as.character(right_score$score), "I")

  contradictory <- accepted
  contradictory$result <- "The release channel is not stable; use beta."
  contradictory_score <- scorer(contradictory)
  expect_identical(
    contradictory_score$scorer_metadata[[1]]$answer_quality,
    "incorrect"
  )

  signed_value <- accepted
  signed_value$result <- "-7"
  expect_identical(
    scorer(signed_value)$scorer_metadata[[1]]$answer_quality,
    "incorrect"
  )

  suffixed_percent <- instruction
  suffixed_percent$result <- "7%"
  expect_identical(
    scorer(suffixed_percent)$scorer_metadata[[1]]$answer_quality,
    "incorrect"
  )

  suffixed_hyphen <- instruction
  suffixed_hyphen$result <- "7-"
  expect_identical(
    scorer(suffixed_hyphen)$scorer_metadata[[1]]$answer_quality,
    "incorrect"
  )

  decimal_window <- samples[samples$case == "corrected", ]
  decimal_window$result <- "6.0 days"
  expect_identical(
    scorer(decimal_window)$scorer_metadata[[1]]$answer_quality,
    "incorrect"
  )

  missing_evidence <- accepted
  missing_evidence$solver_chat <- list(NULL)
  missing_evidence_score <- scorer(missing_evidence)
  expect_identical(
    missing_evidence_score$scorer_metadata[[1]]$evidence_integrity,
    "broken"
  )

  trace <- helpers$graft_recall_eval_trace(accepted$solver_chat[[1]])
  trace$request_names <- "other_tool"
  expect_identical(
    helpers$graft_recall_eval_evidence_ok(trace, fixture$cases$accepted),
    FALSE
  )
})
