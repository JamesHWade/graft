test_that("mcptools stdio exposes read-only recall and synthetic content", {
  skip_if_not_installed("mcptools", "1.0.1")
  skip_if_not_installed("callr")
  skip_if_not_installed("pkgload")

  source_root <- if (pkgload::is_dev_package("graft")) {
    getNamespaceInfo(asNamespace("graft"), "path")
  } else {
    ""
  }
  work_dir <- withr::local_tempdir("graft-mcp-")
  store_path <- file.path(work_dir, "store")
  server_path <- file.path(work_dir, "server.R")
  config_path <- file.path(work_dir, "config.json")
  client_log <- file.path(work_dir, "client.log")

  store <- graft_store(store_path, create = TRUE)
  note <- graft_save(
    store,
    "A synthetic MCP recall.",
    id = "topic",
    media_type = "text/plain"
  )
  invisible(graft_accept(
    store,
    note,
    stream = "topic",
    expected = NULL,
    key = "review-1",
    actor = "test",
    reason = "Synthetic test",
    purpose = "test"
  ))

  writeLines(
    c(
      "if (nzchar(Sys.getenv('GRAFT_SOURCE_ROOT'))) {",
      "  pkgload::load_all(Sys.getenv('GRAFT_SOURCE_ROOT'), quiet = TRUE)",
      "} else {",
      "  library(graft)",
      "}",
      "store <- graft_store(Sys.getenv('GRAFT_MCP_STORE'))",
      "memory_tool <- graft_tool(",
      "  store,",
      "  stream = \"topic\",",
      "  purpose = \"test\",",
      "  eligible = function() TRUE",
      ")",
      "mcptools::mcp_server(",
      "  tools = list(memory_tool),",
      "  session_tools = FALSE",
      ")"
    ),
    server_path
  )

  libraries <- .libPaths()
  server_env <- c(
    GRAFT_SOURCE_ROOT = source_root,
    GRAFT_MCP_STORE = store_path,
    R_LIBS = paste(libraries, collapse = .Platform$path.sep)
  )
  jsonlite::write_json(
    list(
      mcpServers = list(
        graft = list(
          command = "Rscript",
          args = list(server_path),
          env = as.list(server_env)
        )
      )
    ),
    config_path,
    auto_unbox = TRUE
  )

  result <- callr::r(
    function(config_path, client_log) {
      Sys.setenv(MCPTOOLS_CLIENT_LOG = client_log)
      tools <- mcptools::mcp_tools(config_path)
      tool <- tools[[1L]]
      list(
        name = tool@name,
        value = tool(),
        log = readLines(client_log)
      )
    },
    args = list(config_path, client_log),
    timeout = 60
  )

  server_messages <- grep(
    "^FROM SERVER: ",
    result$log,
    value = TRUE
  )
  responses <- lapply(
    sub("^FROM SERVER: ", "", server_messages),
    jsonlite::fromJSON,
    simplifyVector = FALSE
  )
  tools_response <- Filter(
    \(response) !is.null(response$result$tools),
    responses
  )[[1L]]
  expect_length(tools_response$result$tools, 1L)
  payload <- jsonlite::fromJSON(result$value, simplifyVector = FALSE)

  expect_identical(result$name, "recall_project_memory")
  expect_identical(
    tools_response$result$tools[[1L]]$name,
    "recall_project_memory"
  )
  expect_identical(
    tools_response$result$tools[[1L]]$annotations$readOnlyHint,
    TRUE
  )
  expect_identical(
    tools_response$result$tools[[1L]]$annotations$openWorldHint,
    FALSE
  )
  expect_identical(
    tools_response$result$tools[[1L]]$annotations$destructiveHint,
    FALSE
  )
  expect_identical(payload$status, "accepted")
  expect_identical(payload$artifacts[[1L]]$data, "A synthetic MCP recall.")
})
