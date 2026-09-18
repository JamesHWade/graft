test_that("vocabulary releases preserve exact sources, exports and context", {
  fixture <- local_vocabulary()
  selection <- graft_vocabulary_publish(fixture$store, fixture$path)
  released <- graft_vocabulary_read(fixture$store, selection)
  expect_identical(
    graft_vocabulary_publish(fixture$store, fixture$path),
    selection
  )
  expect_identical(released$bindings$release, "urn:example:bindings:v1")
  expect_length(released$dictionaries, 2L)
  expect_match(
    paste(released$context, collapse = "\n"),
    "negated: true",
    fixed = TRUE
  )
  expect_match(
    paste(released$context, collapse = "\n"),
    "do not authorize joins",
    fixed = TRUE
  )
  expect_identical(
    released$references$bindings$sha256,
    digest::digest(file = fixture$path, algo = "sha256")
  )
  revised <- local_vocabulary("v2")
  correction <- graft_vocabulary_publish(fixture$store, revised$path)
  expect_identical(identical(selection, correction), FALSE)
  expect_identical(graft_vocabulary_read(fixture$store, selection), released)
  # Source files and the upstream CLI are unnecessary for historical reads.
  unlink(list.files(
    dirname(fixture$path),
    pattern = "[.](json|yaml)$",
    full.names = TRUE
  ))
  withr::local_envvar(DATA_DICT = "/missing/data-dict")
  reopened <- graft_artifact_store(file.path(
    dirname(fixture$path),
    "artifacts"
  ))
  expect_identical(graft_vocabulary_read(reopened, selection), released)
  restored <- callr::r(
    function(checkout, path, selection) {
      if (!is.null(checkout)) {
        pkgload::load_all(checkout, quiet = TRUE)
      }
      graft::graft_vocabulary_read(graft::graft_artifact_store(path), selection)
    },
    args = list(
      checkout = if (pkgload::is_dev_package("graft")) {
        normalizePath(test_path("../.."))
      } else {
        NULL
      },
      path = file.path(dirname(fixture$path), "artifacts"),
      selection = selection
    )
  )
  expect_identical(restored, released)
  expect_identical(
    graft_vocabulary_read(reopened, correction)$bindings$release,
    "urn:example:bindings:v2"
  )
})

test_that("vocabulary publication rejects ambiguous and invalid bindings", {
  fixture <- local_vocabulary()
  original <- jsonlite::read_json(fixture$path)
  variants <- list(
    missing_field = function(x) {
      x$bindings[[1]]$field <- "absent"
      x
    },
    ambiguous = function(x) {
      y <- x$bindings[[1]]
      y$id <- "duplicate"
      x$bindings <- c(x$bindings, list(y))
      x
    },
    direction = function(x) {
      x$bindings[[4]]$from <- "sample_id"
      x
    },
    qualifiers = function(x) {
      x$bindings[[4]]$grain <- "different grain"
      x
    },
    digest = function(x) {
      x$dictionaries[[1]]$sha256 <- strrep("0", 64)
      x
    },
    traversal = function(x) {
      x$dictionaries[[1]]$path <- "../lab-a.yaml"
      x
    },
    duplicate_dictionary = function(x) {
      x$dictionaries <- c(x$dictionaries, x$dictionaries[1])
      x
    }
  )
  for (mutate in variants) {
    jsonlite::write_json(mutate(original), fixture$path, auto_unbox = TRUE)
    expect_error(
      graft_vocabulary_publish(fixture$store, fixture$path),
      class = "graft_vocabulary_error"
    )
  }
})

test_that("vocabulary reads verify the source and generated context closure", {
  fixture <- local_vocabulary()
  selection <- graft_vocabulary_publish(fixture$store, fixture$path)
  selected <- graft_artifact_read_selection(fixture$store, selection)
  root <- graft_artifact_read(fixture$store, selected$roots[[1]])
  value <- jsonlite::fromJSON(rawToChar(root$bytes), simplifyVector = FALSE)
  value$references$context <- graft_artifact_save(
    fixture$store,
    "wrong-context",
    charToRaw("misleading"),
    "text/markdown"
  )
  altered <- graft_artifact_save(
    fixture$store,
    "altered-release",
    vocabulary_encode(value),
    "application/json",
    vocabulary_dependencies(value$references)
  )
  altered <- graft_artifact_select(fixture$store, list(altered))
  expect_error(
    graft_vocabulary_read(fixture$store, altered),
    "context differs",
    class = "graft_vocabulary_error"
  )
})

test_that("plain R and Commons consume the same published release", {
  skip_if_not_installed("commons")
  fixture <- local_vocabulary()
  release <- graft_vocabulary_read(
    fixture$store,
    graft_vocabulary_publish(fixture$store, fixture$path)
  )
  bindings <- Filter(
    \(x) x$kind == "concept" && x$term == "urn:example:temperature",
    release$bindings$bindings
  )
  expect_identical(
    vapply(bindings, \(x) x$field, character(1)),
    c("temperature_c", "temperature_f")
  )
  expect_identical(
    vapply(bindings, \(x) x$scope, character(1)),
    c("lab-a", "lab-b")
  )
  context_path <- withr::local_tempfile(fileext = ".md")
  writeLines(release$context, context_path)
  expect_s3_class(
    commons::context_layer(files = context_path),
    "commons_context_layer"
  )
  source <- commons::data_source(
    readings = data.frame(
      reading_id = "r1",
      sample_id = "s1",
      temperature_c = 20
    ),
    dictionary = file.path(dirname(fixture$path), "lab-a.yaml")
  )
  expect_s3_class(source, "commons_data_source")
})

test_that("invalid dictionary sources fail through public upstream validation", {
  fixture <- local_vocabulary()
  path <- file.path(dirname(fixture$path), "lab-a.yaml")
  writeLines("not: [valid", path)
  companion <- jsonlite::read_json(fixture$path)
  companion$dictionaries[[1L]]$sha256 <- digest::digest(
    file = path,
    algo = "sha256"
  )
  jsonlite::write_json(companion, fixture$path, auto_unbox = TRUE)
  expect_error(
    graft_vocabulary_publish(fixture$store, fixture$path),
    "data-dict validation/export failed",
    class = "graft_vocabulary_error"
  )
})

test_that("malformed nested JSON fails with vocabulary errors", {
  fixture <- local_vocabulary()
  original <- jsonlite::read_json(fixture$path)
  vocabulary_path <- file.path(dirname(fixture$path), "vocabulary.json")
  original_vocabulary <- readBin(
    vocabulary_path,
    "raw",
    n = file.info(vocabulary_path)$size
  )
  for (bad in list("scalar", NULL, list())) {
    writeBin(original_vocabulary, vocabulary_path)
    for (field in c("vocabulary", "dictionaries", "bindings", "assertions")) {
      candidate <- original
      if (field == "vocabulary") {
        candidate[field] <- list(bad)
      } else {
        candidate[[field]][1L] <- list(bad)
      }
      jsonlite::write_json(
        candidate,
        fixture$path,
        auto_unbox = TRUE,
        null = "null"
      )
      expect_error(
        graft_vocabulary_publish(fixture$store, fixture$path),
        class = "graft_vocabulary_error"
      )
    }
    path <- file.path(dirname(fixture$path), "vocabulary.json")
    vocabulary <- jsonlite::read_json(path)
    vocabulary$terms[1L] <- list(bad)
    jsonlite::write_json(vocabulary, path, auto_unbox = TRUE, null = "null")
    candidate <- original
    candidate$vocabulary$sha256 <- digest::digest(file = path, algo = "sha256")
    jsonlite::write_json(candidate, fixture$path, auto_unbox = TRUE)
    expect_error(
      graft_vocabulary_publish(fixture$store, fixture$path),
      class = "graft_vocabulary_error"
    )
  }
})

test_that("historical vocabulary reads reject malformed artifact references", {
  fixture <- local_vocabulary()
  selection <- graft_vocabulary_publish(fixture$store, fixture$path)
  selected <- graft_artifact_read_selection(fixture$store, selection)
  root <- graft_artifact_read(fixture$store, selected$roots[[1L]])
  original <- jsonlite::fromJSON(rawToChar(root$bytes), simplifyVector = FALSE)
  for (field in c("bindings", "vocabulary", "context", "source", "export")) {
    for (bad in list("scalar", NULL, list())) {
      candidate <- original
      if (field %in% c("source", "export")) {
        candidate$references$dictionaries[[1L]][field] <- list(bad)
      } else {
        candidate$references[field] <- list(bad)
      }
      ref <- graft_artifact_save(
        fixture$store,
        "malformed-release",
        vocabulary_encode(candidate),
        "application/json",
        root$metadata$dependencies
      )
      altered <- graft_artifact_select(fixture$store, list(ref))
      expect_error(
        graft_vocabulary_read(fixture$store, altered),
        class = "graft_vocabulary_error"
      )
    }
  }
})

test_that("dictionary commands reject executable changes after either command", {
  fixture <- local_vocabulary()
  for (change_after in 1:2) {
    commands <- character()
    with_mocked_bindings(
      expect_error(
        vocabulary_read_dictionary(charToRaw("schema: test")),
        "executable changed",
        class = "graft_vocabulary_error"
      ),
      vocabulary_dictionary_command = function(command, path) {
        commands <<- c(commands, command)
        list(status = 0L, output = "{}")
      },
      vocabulary_file_hash = function(path) {
        strrep(if (length(commands) >= change_after) "b" else "a", 64L)
      }
    )
    expect_identical(
      commands,
      c("validate-spec", "export-spec")[seq_len(change_after)]
    )
  }
})

test_that("retained validation provenance requires a version and exact binary digest", {
  fixture <- local_vocabulary()
  selection <- graft_vocabulary_publish(fixture$store, fixture$path)
  selected <- graft_artifact_read_selection(fixture$store, selection)
  root <- graft_artifact_read(fixture$store, selected$roots[[1L]])
  original <- vocabulary_json(root$bytes)
  export <- vocabulary_json(
    graft_artifact_read(
      fixture$store,
      original$references$dictionaries[[1L]]$export
    )$bytes
  )
  for (field in c("package_version", "binary_sha256")) {
    for (bad in list(NULL, 123, list(), "", "not-a-version-or-digest")) {
      candidate <- export
      candidate[field] <- list(bad)
      value <- original
      value$references$dictionaries[[1L]]$export <- graft_artifact_save(
        fixture$store,
        "invalid-export",
        vocabulary_encode(candidate),
        "application/json"
      )
      ref <- graft_artifact_save(
        fixture$store,
        "invalid-provenance",
        vocabulary_encode(value),
        "application/json",
        vocabulary_dependencies(value$references)
      )
      expect_error(
        graft_vocabulary_read(
          fixture$store,
          graft_artifact_select(fixture$store, list(ref))
        ),
        "data-dict",
        class = "graft_vocabulary_error"
      )
    }
  }
})

test_that("historical companion references require sibling paths", {
  fixture <- local_vocabulary()
  selection <- graft_vocabulary_publish(fixture$store, fixture$path)
  selected <- graft_artifact_read_selection(fixture$store, selection)
  root <- graft_artifact_read(fixture$store, selected$roots[[1L]])
  original <- vocabulary_json(root$bytes)
  companion <- jsonlite::read_json(fixture$path)
  for (field in c("vocabulary", "dictionary")) {
    candidate <- companion
    if (field == "vocabulary") {
      candidate$vocabulary$path <- "../vocabulary.json"
    } else {
      candidate$dictionaries[[1L]]$path <- "../lab-a.yaml"
    }
    value <- original
    value$references$bindings <- graft_artifact_save(
      fixture$store,
      "invalid-companion",
      vocabulary_encode(candidate),
      "application/json"
    )
    ref <- graft_artifact_save(
      fixture$store,
      "invalid-path",
      vocabulary_encode(value),
      "application/json",
      vocabulary_dependencies(value$references)
    )
    expect_error(
      graft_vocabulary_read(
        fixture$store,
        graft_artifact_select(fixture$store, list(ref))
      ),
      "Pinned files must be siblings",
      class = "graft_vocabulary_error"
    )
  }
})

test_that("vocabulary failures retain the package error boundary and source bounds", {
  expect_error(
    vocabulary_parse_dictionary_export("{broken"),
    class = "graft_vocabulary_error"
  )
  expect_error(
    vocabulary_parse_dictionary_export("{broken"),
    class = "graft_error"
  )
  path <- withr::local_tempfile()
  for (bytes in list(raw(), raw(1024^2 + 1L))) {
    writeBin(bytes, path)
    expect_error(
      vocabulary_source_bytes(path),
      "1 byte to 1 MiB",
      class = "graft_vocabulary_error"
    )
  }
})

test_that("context renders release-controlled Markdown as literal data", {
  fixture <- local_vocabulary()
  companion <- jsonlite::read_json(fixture$path)
  injected <- "```\n# Injected\n<script>bad()</script>\n![image](https://example.invalid/image)"
  companion$assertions[[1L]]$source <- injected
  jsonlite::write_json(companion, fixture$path, auto_unbox = TRUE)
  release <- graft_vocabulary_read(
    fixture$store,
    graft_vocabulary_publish(fixture$store, fixture$path)
  )
  html <- commonmark::markdown_html(paste(release$context, collapse = "\n"))
  expect_identical(grepl("<script|<img|<h1>Injected", html), FALSE)
  expect_match(html, "&lt;script&gt;", fixed = TRUE)
  expect_identical(release$bindings$assertions[[1L]]$source, injected)
})

test_that("impossible vocabulary releases fail before CLI work or artifact writes", {
  path <- withr::local_tempdir()
  example <- system.file("examples", "vocabulary", "v1", package = "graft")
  file.copy(list.files(example, full.names = TRUE), path)
  companion_path <- file.path(path, "bindings.json")
  original <- jsonlite::read_json(companion_path)
  store <- graft_artifact_store(file.path(path, "artifacts"), create = TRUE)
  before <- list.files(store$path, recursive = TRUE, all.files = TRUE)
  commands <- character()
  local_mocked_bindings(vocabulary_dictionary_command = function(
    command,
    path
  ) {
    commands <<- c(commands, command)
    stop("data-dict should not run")
  })

  oversized <- original
  oversized$dictionaries <- c(
    original$dictionaries,
    lapply(seq_len(497L), function(i) {
      ref <- original$dictionaries[[1L]]
      ref$id <- paste0("extra-dictionary:", i)
      ref
    })
  )
  jsonlite::write_json(oversized, companion_path, auto_unbox = TRUE)
  expect_error(
    graft_vocabulary_publish(store, companion_path),
    "at most 498 dictionaries",
    class = "graft_vocabulary_error"
  )
  expect_identical(commands, character())
  expect_identical(
    list.files(store$path, recursive = TRUE, all.files = TRUE),
    before
  )

  jsonlite::write_json(original, companion_path, auto_unbox = TRUE)
  source_paths <- file.path(
    path,
    c(
      "bindings.json",
      original$vocabulary$path,
      vapply(original$dictionaries, \(ref) ref$path, character(1))
    )
  )
  bounded <- graft_artifact_store(
    store$path,
    max_bytes = sum(file.info(source_paths)$size) - 1L
  )
  expect_error(
    graft_vocabulary_publish(bounded, companion_path),
    "Source files exceed",
    class = "graft_vocabulary_error"
  )
  expect_identical(commands, character())
  expect_identical(
    list.files(store$path, recursive = TRUE, all.files = TRUE),
    before
  )
})


test_that("generated vocabulary payloads are bounded before artifact writes", {
  x <- local_vocabulary()
  selection <- graft_vocabulary_publish(x$store, x$path)
  refs <- graft_artifact_read_selection(x$store, selection)$artifacts
  size <- sum(vapply(
    refs,
    function(ref) {
      length(graft_artifact_read(x$store, ref)$bytes)
    },
    integer(1)
  ))
  target <- file.path(withr::local_tempdir(), "bounded")
  store <- graft_artifact_store(target, create = TRUE, max_bytes = size - 1L)
  before <- list.files(target, recursive = TRUE, all.files = TRUE)
  expect_error(
    graft_vocabulary_publish(store, x$path),
    "Release exceeds the artifact store's aggregate byte limit",
    class = "graft_vocabulary_error"
  )
  expect_identical(
    list.files(target, recursive = TRUE, all.files = TRUE),
    before
  )
  small_metadata <- graft_artifact_store(target, max_revision_bytes = 1L)
  expect_error(
    graft_vocabulary_publish(small_metadata, x$path),
    "Release exceeds the artifact revision byte limit",
    class = "graft_vocabulary_error"
  )
  expect_identical(
    list.files(target, recursive = TRUE, all.files = TRUE),
    before
  )
  exact <- graft_artifact_store(target, max_bytes = size)
  expect_identical(graft_vocabulary_publish(exact, x$path), selection)
})
