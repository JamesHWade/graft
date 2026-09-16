experiment_checkout <- getOption("graft.experiment.checkout")
sys.source(
  file.path(experiment_checkout, "tools/experiments/runtime.R"),
  environment()
)
