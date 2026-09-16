source("tools/experiments/runtime.R")
experiment_prepare(fts = TRUE)
# Run from the repository root. Optional argument: output directory.
source("tools/experiments/vocabulary/publisher.R")
args <- commandArgs(trailingOnly = TRUE)
out <- if (length(args)) args[[1]] else tempfile("vocabulary-results-")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
fixture <- "tools/experiments/vocabulary/fixtures"
v1 <- publish_bindings(file.path(fixture, "v1", "bindings.json"))
v2 <- publish_bindings(file.path(fixture, "v2", "bindings.json"))
frames <- list(
  `lab-a` = list(
    readings = data.frame(
      reading_id = c("r1", "r2"),
      sample_id = c("s1", "s2"),
      temperature_c = c(20, 21)
    )
  ),
  `lab-b` = list(
    assays = data.frame(
      assay_id = c("a1", "a2"),
      specimen = c("s1", "s2"),
      temperature_f = c(104, 105)
    )
  )
)

# Mutate copies only. Refresh a digest only when deliberately authoring a new
# candidate; stale digest rejection is tested separately.
candidate <- function(edit) {
  dest <- tempfile("binding-candidate-")
  dir.create(dest)
  file.copy(list.files(file.path(fixture, "v1"), full.names = TRUE), dest)
  on.exit(unlink(dest, recursive = TRUE), add = TRUE)
  path <- file.path(dest, "bindings.json")
  b <- edit(read_json(path), dest)
  jsonlite::write_json(b, path, auto_unbox = TRUE, pretty = TRUE)
  publish_bindings(path)
}

cases <- character()
case <- function(name, code) {
  testthat::test_that(name, code)
  cases <<- c(cases, name)
}

case("both independently authored schemas validate through public data-dict", {
  testthat::expect_length(v1$dictionaries, 2L)
  testthat::expect_identical(
    lapply(v1$dictionaries, \(x) x$evidence$status),
    list(
      `urn:example:dictionary:lab-a:v1` = 0L,
      `urn:example:dictionary:lab-b:v1` = 0L
    )
  )
})
case("dictionary exports tolerate diagnostics but reject missing or ambiguous JSON", {
  testthat::expect_identical(
    parse_dictionary_export(c("Warning: diagnostic", '{"tables":[]}', "Done")),
    list(tables = list())
  )
  for (output in list("Warning: no export", c("{}", "{}"))) {
    testthat::expect_error(
      parse_dictionary_export(output),
      "Expected one JSON document",
      class = "fixture_binding_error"
    )
  }
})
case("relationship endpoints are scalar stable identifiers even when unused", {
  for (endpoint in c("domain", "range")) {
    for (value in list(1, NULL, list("urn:example:sample"), "")) {
      testthat::expect_error(
        candidate(function(b, dir) {
          vpath <- file.path(dir, b$vocabulary$path)
          v <- read_json(vpath)
          term <- list(
            id = "urn:example:unused",
            kind = "relationship",
            definition = "Unused relationship",
            aliases = list(),
            domain = "urn:example:sample",
            range = "urn:example:sample"
          )
          term[endpoint] <- list(value)
          v$terms <- c(v$terms, list(term))
          jsonlite::write_json(v, vpath, auto_unbox = TRUE, null = "null")
          b$vocabulary$sha256 <- file_hash(vpath)
          b
        }),
        "relationship endpoint must be a nonempty string",
        class = "fixture_binding_error"
      )
    }
  }
})
case("plain R resolves shared sample values without a chat", {
  for (workflow in names(frames)) {
    imported <- import_concept(
      v1,
      workflow,
      frames[[workflow]],
      "urn:example:sample"
    )
    testthat::expect_identical(imported$values, c("s1", "s2"))
    testthat::expect_identical(imported$binding$scope, workflow)
  }
})
case("changed or missing bound fields fail rather than repairing the mapping", {
  testthat::expect_error(
    candidate(function(b, dir) {
      b$bindings[[2]]$field <- "renamed_sample_id"
      b
    }),
    "Missing or ambiguous bound field",
    class = "fixture_binding_error"
  )
  wrong <- frames$`lab-a`
  wrong$readings$sample_id <- NULL
  testthat::expect_error(
    import_concept(v1, "lab-a", wrong, "urn:example:sample"),
    "missing its bound field",
    class = "fixture_binding_error"
  )
})
case("release references are scalar and assertion identities are unique", {
  testthat::expect_error(
    candidate(function(b, dir) {
      b$vocabulary$release <- c(
        "urn:example:vocabulary:v1",
        "urn:example:vocabulary:v2"
      )
      b
    }),
    "nonempty string",
    class = "fixture_binding_error"
  )
  testthat::expect_error(
    candidate(function(b, dir) {
      b$assertions[[2]]$id <- b$assertions[[1]]$id
      b
    }),
    "Duplicate assertion ID",
    class = "fixture_binding_error"
  )
})
case("unknown terms fail", {
  testthat::expect_error(
    candidate(function(b, dir) {
      b$bindings[[2]]$term <- "urn:example:unknown"
      b
    }),
    "Unknown term",
    class = "fixture_binding_error"
  )
})
case("relationship terms cannot be used as concept bindings", {
  testthat::expect_error(
    candidate(function(b, dir) {
      b$bindings[[2]]$term <- "urn:example:measurement-of-sample"
      b
    }),
    "Wrong binding kind",
    class = "fixture_binding_error"
  )
})
case("ambiguous field equivalence fails", {
  testthat::expect_error(
    candidate(function(b, dir) {
      duplicate <- b$bindings[[2]]
      duplicate$id <- "competing-sample-mapping"
      duplicate$term <- "urn:example:measurement"
      b$bindings <- c(b$bindings, list(duplicate))
      b
    }),
    "Ambiguous equivalence",
    class = "fixture_binding_error"
  )
})
case("reversed relationship direction fails", {
  testthat::expect_error(
    candidate(function(b, dir) {
      b$bindings[[4]]$from <- "sample_id"
      b$bindings[[4]]$to <- "reading_id"
      b
    }),
    "direction/domain/range",
    class = "fixture_binding_error"
  )
})
case("vocabulary release and content mismatch fail independently", {
  testthat::expect_error(
    candidate(function(b, dir) {
      b$vocabulary$release <- "urn:example:vocabulary:v2"
      b
    }),
    "release mismatch",
    class = "fixture_binding_error"
  )
  testthat::expect_error(
    candidate(function(b, dir) {
      cat("\n", file = file.path(dir, b$vocabulary$path), append = TRUE)
      b
    }),
    "changed pinned content",
    class = "fixture_binding_error"
  )
})
case("a changed dictionary is rejected before binding validation", {
  testthat::expect_error(
    candidate(function(b, dir) {
      path <- file.path(dir, b$dictionaries[[1]]$path)
      writeLines(gsub("sample_id", "renamed_sample_id", readLines(path)), path)
      b
    }),
    "changed pinned content",
    class = "fixture_binding_error"
  )
})
case("a repinned renamed dictionary still requires a new binding", {
  testthat::expect_error(
    candidate(function(b, dir) {
      path <- file.path(dir, b$dictionaries[[1]]$path)
      writeLines(gsub("sample_id", "renamed_sample_id", readLines(path)), path)
      b$dictionaries[[1]]$sha256 <- file_hash(path)
      b
    }),
    "Missing or ambiguous bound field",
    class = "fixture_binding_error"
  )
})
case("unexpected qualifier fields are rejected rather than silently dropped", {
  testthat::expect_error(
    candidate(function(b, dir) {
      b$assertions[[1]]$unsupported_confidence <- 0.9
      b
    }),
    "unsupported fields",
    class = "fixture_binding_error"
  )
})
case("machine and prose records preserve exact direction and all qualifiers", {
  lines <- render_context(v1)
  json_lines <- lines[startsWith(lines, "{")]
  decoded <- lapply(json_lines, jsonlite::fromJSON, simplifyVector = FALSE)
  for (record in c(
    v1$vocabulary$terms,
    v1$bindings$dictionaries,
    v1$bindings$bindings,
    v1$bindings$assertions
  )) {
    testthat::expect_identical(
      sum(vapply(decoded, identical, logical(1), record)),
      1L
    )
  }
  retracted <- lines[startsWith(lines, "Assertion `assertion:2`")]
  testthat::expect_length(retracted, 1L)
  for (value in c(
    "Status: retracted",
    "negated: true",
    "time: 2026-09-02",
    "scope: lab-b"
  )) {
    testthat::expect_match(retracted, value, fixed = TRUE)
  }
  testthat::expect_identical(v1$bindings$assertions[[2]]$negated, TRUE)
  testthat::expect_identical(v1$bindings$assertions[[2]]$status, "retracted")
  testthat::expect_identical(
    sum(grepl(v1$vocabulary$release, lines, fixed = TRUE)),
    1L
  )
  testthat::expect_identical(
    sum(grepl(v1$bindings$release, lines, fixed = TRUE)),
    1L
  )
})
case("shared terms do not establish safe comparisons or joins", {
  testthat::expect_error(
    check_comparison(v1, "lab-a:temperature_c", "lab-b:temperature_f"),
    "units, grain, conditions, and identity scope",
    class = "fixture_binding_error"
  )
  testthat::expect_error(
    check_comparison(v1, "lab-a:sample_id", "lab-b:specimen"),
    "identity scope",
    class = "fixture_binding_error"
  )
})
case("a new release renames a field while the earlier release replays exactly", {
  updated <- frames$`lab-b`
  names(updated$assays)[2] <- "specimen_id"
  testthat::expect_identical(
    import_concept(v2, "lab-b", updated, "urn:example:sample")$binding$field,
    "specimen_id"
  )
  replay <- publish_bindings(file.path(fixture, "v1", "bindings.json"))
  testthat::expect_identical(replay, v1)
  testthat::expect_identical(render_context(replay), render_context(v1))
  testthat::expect_error(
    import_concept(v1, "lab-b", updated, "urn:example:sample"),
    "missing its bound field",
    class = "fixture_binding_error"
  )
})

context_path <- file.path(out, "context-v1.md")
writeLines(render_context(v1), context_path, useBytes = TRUE)
case("Commons public constructors consume the same context and local dictionaries", {
  context <- commons::context_layer(files = context_path)
  testthat::expect_s3_class(context, "commons_context_layer")
  sources <- lapply(v1$bindings$dictionaries, function(ref) {
    do.call(
      commons::data_source,
      c(
        frames[[ref$workflow]],
        list(dictionary = file.path(fixture, "v1", ref$path))
      )
    )
  })
  for (src in sources) {
    testthat::expect_s3_class(src, "commons_data_source")
  }
})

jsonlite::write_json(
  v1,
  file.path(out, "published-v1.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
jsonlite::write_json(
  v2,
  file.path(out, "published-v2.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
result <- list(
  cases = cases,
  passed = length(cases),
  versions = list(
    R = as.character(getRversion()),
    commons = as.character(utils::packageVersion("commons")),
    datadict = as.character(utils::packageVersion("datadict")),
    data_dict = datadict::dd_run("--version")$output,
    cli_binary_sha256 = file_hash(datadict::dd_path()),
    packages = lapply(
      stats::setNames(
        c("jsonlite", "cli", "testthat", "ellmer", "duckdb", "yaml"),
        c("jsonlite", "cli", "testthat", "ellmer", "duckdb", "yaml")
      ),
      function(package) as.character(utils::packageVersion(package))
    )
  ),
  source_pins = list(
    commons = utils::packageDescription("commons")$RemoteSha,
    data_dict = utils::packageDescription("datadict")$RemoteSha
  ),
  references = v1$references,
  limitations = c(
    "Constructor consumption only; Commons model/tool roundtrip belongs to #62.",
    "Spec/binding/import-field checks are not full data-value validation.",
    "Comparison guard is deliberately narrow; no conversion, join planner, reasoner or authorization proof."
  )
)
jsonlite::write_json(
  result,
  file.path(out, "results.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
cat(
  "Vocabulary experiment:",
  length(cases),
  "cases passed. Results:",
  out,
  "\n"
)
