test_that("the app rejects a stale displayed review predecessor", {
  skip_if_not_installed("bslib")
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat")

  app_path <- system.file(
    "examples",
    "project-memory",
    "app.R",
    package = "graft"
  )
  if (
    app_path == "" || !file.exists(file.path(dirname(app_path), "memory.R"))
  ) {
    app_path <- test_path(
      "..",
      "..",
      "inst",
      "examples",
      "project-memory",
      "app.R"
    )
  }
  app_path <- normalizePath(app_path, winslash = "/", mustWork = TRUE)
  expect_identical(file.exists(app_path), TRUE)

  store_path <- withr::local_tempdir()
  withr::local_envvar(c(
    GRAFT_DEMO_STORE = store_path,
    GRAFT_DEMO_LIVE = "false"
  ))
  app <- new.env(parent = globalenv())
  withr::local_dir(dirname(app_path))
  sys.source(app_path, envir = app)

  shiny::testServer(app$server, {
    session$setInputs(
      memory_note = "Initial reviewed definition",
      memory_source = "Source one",
      save_memory = 1
    )
    first <- app$read_project_memory(
      app$open_project_memory(store_path)
    )

    external <- app$save_project_memory(
      app$open_project_memory(store_path),
      note = "External correction",
      source = "Source two",
      expected = first$decision_id
    )

    session$setInputs(
      memory_note = "Stale app correction",
      memory_source = "Stale source",
      save_memory = 2
    )

    current <- app$read_project_memory(
      app$open_project_memory(store_path)
    )
    expect_identical(current$decision_id, external$decision_id)
    expect_identical(current$note, external$note)
    expect_identical(current$source, external$source)

    displayed <- as.character(session$getOutput("memory_state")$html)
    expect_match(displayed, "Initial reviewed definition", fixed = TRUE)
    expect_identical(
      grepl("Stale app correction", displayed, fixed = TRUE),
      FALSE
    )
  })
})

test_that("offline save and new-conversation actions stay usable", {
  skip_if_not_installed("bslib")
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat")

  app_path <- system.file(
    "examples",
    "project-memory",
    "app.R",
    package = "graft"
  )
  if (
    app_path == "" || !file.exists(file.path(dirname(app_path), "memory.R"))
  ) {
    app_path <- test_path(
      "..",
      "..",
      "inst",
      "examples",
      "project-memory",
      "app.R"
    )
  }
  app_path <- normalizePath(app_path, winslash = "/", mustWork = TRUE)
  expect_identical(file.exists(app_path), TRUE)

  store_path <- withr::local_tempdir()
  withr::local_envvar(c(
    GRAFT_DEMO_STORE = store_path,
    GRAFT_DEMO_LIVE = "false"
  ))
  app <- new.env(parent = globalenv())
  withr::local_dir(dirname(app_path))
  sys.source(app_path, envir = app)

  shiny::testServer(app$server, {
    session$setInputs(
      memory_note = "Reviewed definition",
      memory_source = "Reviewed source",
      save_memory = 1
    )
    saved <- app$read_project_memory(
      app$open_project_memory(store_path)
    )
    expect_identical(saved$status, "accepted")

    session$setInputs(chat_user_input = "How do we count one?")
    session$setInputs(new_conversation = 1)

    current <- app$read_project_memory(
      app$open_project_memory(store_path)
    )
    expect_identical(current$decision_id, saved$decision_id)
    expect_identical(current$note, saved$note)
    expect_identical(current$source, saved$source)
  })
})

test_that("live new-conversation recreates the client without a request", {
  skip_if_not_installed("bslib")
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat")

  app_path <- system.file(
    "examples",
    "project-memory",
    "app.R",
    package = "graft"
  )
  if (
    app_path == "" || !file.exists(file.path(dirname(app_path), "memory.R"))
  ) {
    app_path <- test_path(
      "..",
      "..",
      "inst",
      "examples",
      "project-memory",
      "app.R"
    )
  }
  app_path <- normalizePath(app_path, winslash = "/", mustWork = TRUE)
  expect_identical(file.exists(app_path), TRUE)

  store_path <- withr::local_tempdir()
  withr::local_envvar(c(
    GRAFT_DEMO_STORE = store_path,
    GRAFT_DEMO_LIVE = "true",
    OPENAI_API_KEY = "provider-free-test-key"
  ))
  app <- new.env(parent = globalenv())
  withr::local_dir(dirname(app_path))
  sys.source(app_path, envir = app)

  shiny::testServer(app$server, {
    old_client <- session$env$live_chat$client
    expect_s3_class(old_client, "Chat")
    expect_length(old_client$get_tools(), 1L)
    old_client$set_turns(list(ellmer::UserTurn(
      list(ellmer::ContentText("old conversation"))
    )))
    expect_length(old_client$get_turns(), 1L)

    session$setInputs(new_conversation = 1)

    new_client <- session$env$live_chat$client
    expect_identical(identical(new_client, old_client), FALSE)
    expect_s3_class(new_client, "Chat")
    expect_length(new_client$get_tools(), 1L)
    expect_length(new_client$get_turns(), 0L)
  })
})
