#!/usr/bin/env Rscript

# Run in a fresh R process with the selected ellmer library first in R_LIBS.
# Installation belongs to CI/the caller; this check never calls a provider.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 1L) {
  stop("Supply the expected ellmer version.", call. = FALSE)
}
expected <- arguments[[1L]]
observed <- as.character(utils::packageVersion("ellmer"))
if (!identical(observed, expected)) {
  stop(
    "Expected ellmer ",
    expected,
    "; found ",
    observed,
    " at ",
    find.package("ellmer"),
    call. = FALSE
  )
}
message("Checking ellmer ", observed, " at ", find.package("ellmer"))
devtools::load_all()

if (utils::packageVersion("ellmer") < "0.5.0") {
  chat <- ellmer::chat_openai(model = "gpt-4o-mini")
  chat$set_turns(list(ellmer::Turn(
    role = "assistant",
    contents = list(ellmer::ContentText("A recorded answer"))
  )))
  for (condition in list(
    rlang::catch_cnd(graft_tools(NULL)),
    rlang::catch_cnd(graft_verify(chat))
  )) {
    testthat::expect_s3_class(condition, "rlib_error_package_not_found")
    testthat::expect_identical(condition$pkg, "ellmer")
    testthat::expect_identical(condition$version, "0.5.0")
  }
  message("Unsupported ellmer is rejected before tool or answer processing.")
} else {
  devtools::test(
    filter = "^(agent-tools|verify)$",
    stop_on_failure = TRUE
  )
}
