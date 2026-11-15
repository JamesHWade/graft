test_that("handoff_output preserves binary and text bytes", {
  binary <- as.raw(c(0, 1, 127, 128, 255))
  descriptor <- handoff_output("figure", binary, "image/png")

  expect_identical(descriptor$key, "figure")
  expect_identical(descriptor$media_type, "image/png")
  expect_identical(descriptor$size, 5L)
  expect_identical(
    jsonlite::base64_dec(descriptor$data),
    binary
  )
  expect_identical(
    descriptor$sha256,
    digest::digest(binary, algo = "sha256", serialize = FALSE)
  )

  text <- handoff_output("report", "Résumé", "text/plain")
  expect_identical(
    rawToChar(jsonlite::base64_dec(text$data)),
    "Résumé"
  )

  large <- handoff_output(
    "large",
    as.raw(rep(1L, 500L)),
    "application/octet-stream"
  )
  expect_identical(grepl("[[:space:]]", large$data), FALSE)
  expect_identical(
    jsonlite::base64_dec(large$data),
    as.raw(rep(1L, 500L))
  )
})

test_that("completed outputs retain exact bytes and remain a draft", {
  store_path <- tempfile("handoff-store-")
  withr::defer(unlink(store_path, recursive = TRUE, force = TRUE))
  store <- graft_store(store_path, create = TRUE, max_bytes = 1024^2)
  input <- graft_save(store, "source input", "input:source")
  inputs <- graft_select(store, input)
  completion <- list(
    schema = handoff_schema,
    operation_id = "operation-1",
    state = "complete",
    producer = list(name = "fixture", version = "1"),
    errors = list(),
    outputs = list(
      handoff_output("report", "A report", "text/plain"),
      handoff_output("table", as.raw(c(1, 0, 255)), "application/octet-stream"),
      handoff_output(
        "figure",
        as.raw(rep(137L, 500L)),
        "image/png"
      )
    )
  )

  result <- retain_completed_output(
    store,
    completion,
    inputs,
    id = "run-1",
    eligible = \() TRUE
  )

  expect_identical(names(result$outputs), c("figure", "report", "table"))
  expect_identical(
    graft_read(store, result$outputs$figure)@bytes,
    as.raw(rep(137L, 500L))
  )
  expect_identical(
    graft_read(store, result$outputs$table)@bytes,
    as.raw(c(1, 0, 255))
  )
  evidence <- jsonlite::fromJSON(
    rawToChar(graft_read(store, result$evidence)@bytes),
    simplifyVector = FALSE
  )
  expect_identical(evidence$input_selection_id, inputs@id)
  expect_identical(evidence$outputs[[1]]$key, "figure")
  expect_identical("data" %in% names(evidence$outputs[[1]]), FALSE)
  expect_identical(
    graft_read(store, result$evidence)@dependencies[[1]]@revision,
    input@revision
  )

  recall <- graft_recall(store, "drafts", "research", eligible = TRUE)
  expect_identical(recall@status, "missing")
  decision <- graft_accept(
    store,
    result$root,
    stream = "drafts",
    expected = NULL,
    key = "accept-1",
    actor = "reviewer",
    reason = "reviewed",
    purpose = "research"
  )
  expect_identical(decision@action, "accept")
  accepted <- graft_recall(store, "drafts", "research", eligible = TRUE)
  expect_identical(accepted@status, "accepted")
  expect_identical(
    accepted@roots[[1]]@bytes,
    graft_read(store, result$root)@bytes
  )
})

test_that("retained refs preserve exact bytes and corrected revisions", {
  store_path <- tempfile("handoff-retained-")
  withr::defer(unlink(store_path, recursive = TRUE, force = TRUE))
  store <- graft_store(store_path, create = TRUE, max_bytes = 1024^2)
  input <- graft_save(store, "source input", "input:source")
  inputs <- graft_select(store, input)
  retained_bytes <- as.raw(c(137, 80, 78, 71, 0, 255))
  retained_ref <- graft_save(
    store,
    retained_bytes,
    "existing:figure",
    media_type = "image/png"
  )
  retained_descriptor <- list(
    key = "figure",
    media_type = "image/png",
    size = length(retained_bytes),
    sha256 = digest::digest(retained_bytes, algo = "sha256", serialize = FALSE),
    encoding = "retained",
    ref = list(id = retained_ref@id, revision = retained_ref@revision)
  )
  completion <- list(
    schema = handoff_schema,
    operation_id = "operation-retained",
    state = "complete",
    producer = list(name = "fixture"),
    errors = list(),
    outputs = list(
      retained_descriptor,
      handoff_output("report", "original", "text/plain"),
      handoff_output("table", as.raw(c(1, 2)), "application/octet-stream")
    )
  )

  first <- retain_completed_output(
    store,
    completion,
    inputs,
    id = "run-retained",
    eligible = \() TRUE
  )
  second <- retain_completed_output(
    store,
    completion,
    inputs,
    id = "run-retained",
    eligible = \() TRUE
  )

  expect_identical(first$root, second$root)
  expect_identical(first$evidence, second$evidence)
  expect_identical(first$outputs, second$outputs)
  expect_identical(first$outputs$figure, retained_ref)
  expect_identical(
    graft_read(store, first$outputs$figure)@bytes,
    retained_bytes
  )
  selected <- graft_select(store, first$root)
  selected_keys <- vapply(
    selected@artifacts,
    \(ref) paste(ref@id, ref@revision, sep = "@"),
    character(1)
  )
  expect_identical(
    paste(retained_ref@id, retained_ref@revision, sep = "@") %in% selected_keys,
    TRUE
  )

  corrected <- completion
  corrected$outputs[[2]] <- handoff_output("report", "corrected", "text/plain")
  corrected_result <- retain_completed_output(
    store,
    corrected,
    inputs,
    id = "run-retained",
    eligible = \() TRUE
  )
  expect_identical(identical(corrected_result$root, first$root), FALSE)
  expect_identical(
    graft_read(store, first$outputs$report)@data,
    "original"
  )
  expect_identical(
    graft_read(store, corrected_result$outputs$report)@data,
    "corrected"
  )
})

test_that("malformed packets fail before any draft write", {
  store_path <- tempfile("handoff-invalid-")
  withr::defer(unlink(store_path, recursive = TRUE, force = TRUE))
  store <- graft_store(store_path, create = TRUE, max_bytes = 1024^2)
  input <- graft_save(store, "source input", "input:source")
  inputs <- graft_select(store, input)
  valid <- list(
    schema = handoff_schema,
    operation_id = "operation-invalid",
    state = "complete",
    producer = list(name = "fixture"),
    errors = list(),
    outputs = list(
      handoff_output("report", "report", "text/plain"),
      handoff_output("table", "table", "text/plain"),
      handoff_output("figure", "figure", "text/plain")
    )
  )
  malformed <- list(
    within(valid, {
      state <- "partial"
    }),
    within(valid, {
      schema <- "other/1"
    }),
    within(valid, {
      outputs[[1]]$encoding <- "digest"
    }),
    within(valid, {
      outputs[[1]]$size <- 1024L
    }),
    within(valid, {
      outputs[[1]]$size <- 1L
      outputs[[1]]$data <- strrep("A", 4096L)
    })
  )
  limits <- c(10L, 1024L, 1024L, 1024L, 8L)

  before <- length(graft_manifest(store)$objects)
  for (index in seq_along(malformed)) {
    expect_error(
      retain_completed_output(
        store,
        malformed[[index]],
        inputs,
        id = paste0("invalid-", index),
        eligible = \() TRUE,
        max_bytes = limits[[index]]
      ),
      class = "handoff_error"
    )
  }
  expect_error(
    retain_completed_output(
      store,
      valid,
      inputs,
      id = "invalid-total",
      eligible = \() TRUE,
      max_total_bytes = 1L
    ),
    class = "handoff_error"
  )
  huge_producer <- valid
  huge_producer$producer <- list(name = strrep("x", 20000L))
  expect_error(
    retain_completed_output(
      store,
      huge_producer,
      inputs,
      id = "invalid-producer",
      eligible = \() TRUE,
      max_metadata_bytes = 1024L
    ),
    class = "handoff_error"
  )
  attributed_producer <- valid
  attributed_producer$producer <- structure(
    list(name = "fixture"),
    class = "producer"
  )
  expect_error(
    retain_completed_output(
      store,
      attributed_producer,
      inputs,
      id = "invalid-attributed-producer",
      eligible = \() TRUE
    ),
    class = "handoff_error"
  )
  attributed_atomic <- valid
  attributed_atomic$producer <- list(
    name = structure("fixture", source = "arbitrary")
  )
  expect_error(
    retain_completed_output(
      store,
      attributed_atomic,
      inputs,
      id = "invalid-attributed-atomic",
      eligible = \() TRUE
    ),
    class = "handoff_error"
  )
  after <- length(graft_manifest(store)$objects)
  expect_identical(after, before)
})

test_that("eligibility is checked before writes and while saving", {
  store_path <- tempfile("handoff-gate-")
  withr::defer(unlink(store_path, recursive = TRUE, force = TRUE))
  store <- graft_store(store_path, create = TRUE, max_bytes = 1024^2)
  input <- graft_save(store, "source input", "input:source")
  inputs <- graft_select(store, input)
  completion <- list(
    schema = handoff_schema,
    operation_id = "operation-gate",
    state = "complete",
    producer = list(name = "fixture"),
    errors = list(),
    outputs = list(
      handoff_output("report", "report", "text/plain"),
      handoff_output("table", "table", "text/plain"),
      handoff_output("figure", "figure", "text/plain")
    )
  )

  before <- length(graft_manifest(store)$objects)
  expect_error(
    retain_completed_output(
      store,
      completion,
      inputs,
      id = "denied",
      eligible = \() FALSE
    ),
    class = "handoff_error"
  )
  expect_identical(length(graft_manifest(store)$objects), before)

  calls <- 0L
  before <- length(graft_manifest(store)$objects)
  expect_error(
    retain_completed_output(
      store,
      completion,
      inputs,
      id = "withdrawn",
      eligible = function() {
        calls <<- calls + 1L
        calls < 3L
      }
    ),
    class = "handoff_error"
  )
  expect_identical(calls >= 3L, TRUE)
  expect_identical(length(graft_manifest(store)$objects) > before, TRUE)
})

test_that("closure bounds reject a root that would exceed the store", {
  store_path <- tempfile("handoff-closure-")
  withr::defer(unlink(store_path, recursive = TRUE, force = TRUE))
  store <- graft_store(store_path, create = TRUE, max_bytes = 8192L)
  input <- graft_save(store, as.raw(rep(1L, 7600L)), "input:large")
  inputs <- graft_select(store, input)
  completion <- list(
    schema = handoff_schema,
    operation_id = "operation-closure",
    state = "complete",
    producer = list(name = "fixture"),
    errors = list(),
    outputs = list(
      handoff_output("report", strrep("r", 40L), "text/plain"),
      handoff_output("table", "{}", "application/json"),
      handoff_output("figure", as.raw(1:4), "image/png")
    )
  )
  before <- length(graft_manifest(store)$objects)
  expect_error(
    retain_completed_output(
      store,
      completion,
      inputs,
      id = "closure-overbound",
      eligible = \() TRUE
    ),
    class = "handoff_error"
  )
  expect_identical(length(graft_manifest(store)$objects), before)
})
