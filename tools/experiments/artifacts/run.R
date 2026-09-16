# Run from the repository root with the isolated/pinned experiment library.
options(graft.experiment.checkout = normalizePath("."))
testthat::test_dir("tools/experiments/artifacts/tests", stop_on_failure = TRUE)
