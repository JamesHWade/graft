required_packages <- c("bslib", "graft", "shiny", "tempest")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0L) {
  stop(
    "Install the app dependencies: ",
    paste(missing_packages, collapse = ", ")
  )
}

app_dir <- normalizePath(getwd(), mustWork = TRUE)
example_dir <- normalizePath(file.path(app_dir, ".."), mustWork = TRUE)
app_environment <- environment()
for (path in c(
  file.path(example_dir, "R", "host.R"),
  file.path(example_dir, "R", "blue-sky.R"),
  file.path(example_dir, "R", "scenario.R"),
  file.path(app_dir, "R", "data.R"),
  file.path(app_dir, "R", "presentation.R"),
  file.path(app_dir, "R", "server.R")
)) {
  sys.source(path, envir = app_environment)
}
rm(app_environment, path)

app <- shiny::shinyApp(
  ui = ci_app_ui(),
  server = ci_app_server(example_dir)
)
app
