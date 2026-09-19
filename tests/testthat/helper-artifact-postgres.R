local_artifact_postgres <- function(env = parent.frame()) {
  testthat::skip_if_not_installed("RPostgres")
  testthat::skip_if(
    Sys.getenv("GRAFT_TEST_POSTGRES") != "true",
    "GRAFT_TEST_POSTGRES is not enabled"
  )
  connection <- DBI::dbConnect(RPostgres::Postgres())
  schema <- paste0("graft_test_", basename(tempfile()))
  quoted <- DBI::dbQuoteIdentifier(connection, schema)
  DBI::dbExecute(connection, paste("CREATE SCHEMA", quoted))
  DBI::dbExecute(connection, paste("SET search_path TO", quoted))
  withr::defer(
    {
      try(DBI::dbRollback(connection), silent = TRUE)
      DBI::dbExecute(connection, paste("DROP SCHEMA", quoted, "CASCADE"))
      DBI::dbDisconnect(connection)
    },
    envir = env
  )
  connection
}
