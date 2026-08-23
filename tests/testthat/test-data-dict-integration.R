test_that("graft_schema routes resolved data-dict exports deterministically", {
  source_one <- withr::local_tempfile(fileext = ".json")
  source_two <- withr::local_tempfile(fileext = ".json")
  output_one <- withr::local_tempfile(fileext = ".graft.json")
  output_two <- withr::local_tempfile(fileext = ".graft.json")
  expect_identical(
    file.copy(data_dict_personinfo_export_path(), source_one),
    TRUE
  )
  expect_identical(
    file.copy(data_dict_personinfo_export_path(), source_two),
    TRUE
  )

  first <- graft_schema(source_one, output_one)
  second <- graft_schema(source_two, output_two)

  expect_identical(first@name, "personinfo")
  expect_identical(first@version, "0.1.0")
  expect_setequal(
    names(first@classes),
    c("person", "organization", "person_employment", "GraftDefinition")
  )
  expect_identical(first@structural_digest, second@structural_digest)
  expect_identical(first@source_digest, second@source_digest)
  expect_identical(first@build_digest, second@build_digest)
  read_raw <- function(path) {
    readBin(path, what = "raw", n = file.info(path)$size)
  }
  expect_identical(read_raw(output_one), read_raw(output_two))
  expect_identical(
    first@manifest$dictionary$profile,
    "graft-table-v1"
  )
  expect_identical(
    first@manifest$compiler$provider$source_format,
    "resolved_json"
  )
  expect_identical(
    any(vapply(
      c(source_one, source_two),
      \(path) grepl(path, canonical_json(first@manifest), fixed = TRUE),
      logical(1)
    )),
    FALSE
  )
  expect_identical(
    first@manifest$dictionary$provider,
    first@manifest$compiler$provider
  )
  expect_identical(
    "source_path" %in% names(first@manifest$dictionary$provider),
    FALSE
  )
})

test_that("graft_schema rejects nested resolved constraint arrays", {
  document <- jsonlite::fromJSON(
    data_dict_personinfo_export_path(),
    simplifyVector = FALSE
  )
  document$tables[[1L]]$columns[[1L]]$constraints <- list(
    list("primary_key")
  )
  source <- withr::local_tempfile(fileext = ".json")
  output <- withr::local_tempfile(fileext = ".graft.json")
  writeLines(canonical_json(document), source, useBytes = TRUE)
  writeLines("previous validated artifact", output)

  condition <- rlang::catch_cnd(graft_schema(source, output))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "column_constraints")
  expect_identical(condition$field, "tables[1].columns[1].constraints")
  expect_identical(
    readLines(output, warn = FALSE),
    "previous validated artifact"
  )
})

test_that("graft_schema rejects malformed resolved data versions", {
  document <- jsonlite::fromJSON(
    data_dict_personinfo_export_path(),
    simplifyVector = FALSE
  )
  document$version <- list(
    number = list(nested = "2.4"),
    bogus = "ignored"
  )
  source <- withr::local_tempfile(fileext = ".json")
  writeLines(canonical_json(document), source, useBytes = TRUE)

  condition <- rlang::catch_cnd(graft_schema(source))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "data_version")
  expect_identical(condition$field, "version")
})

test_that("graft_schema rejects invalid data version text before publication", {
  document <- jsonlite::fromJSON(
    data_dict_personinfo_export_path(),
    simplifyVector = FALSE
  )
  document$version <- list(number = "2.4")
  source <- withr::local_tempfile(fileext = ".json")
  output <- withr::local_tempfile(fileext = ".graft.json")
  writeLines(canonical_json(document), source, useBytes = TRUE)
  writeLines("previous validated artifact", output)

  condition <- rlang::catch_cnd(graft_schema(source, output))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "data_version")
  expect_identical(condition$field, "version.number")
  expect_identical(
    readLines(output, warn = FALSE),
    "previous validated artifact"
  )
})

test_that("graft_schema does not infer a foreign key from references alone", {
  document <- jsonlite::fromJSON(
    data_dict_personinfo_export_path(),
    simplifyVector = FALSE
  )
  document$tables[[3L]]$columns[[2L]]$constraints <- as.list("required")
  source <- withr::local_tempfile(fileext = ".json")
  output <- withr::local_tempfile(fileext = ".graft.json")
  writeLines(canonical_json(document), source, useBytes = TRUE)
  writeLines("previous validated artifact", output)

  condition <- rlang::catch_cnd(graft_schema(source, output))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "resolved_foreign_key")
  expect_identical(condition$field, "tables[3].columns[2].references")
  expect_identical(
    readLines(output, warn = FALSE),
    "previous validated artifact"
  )
})

test_that("graft_schema requires resolved enum arrays", {
  document <- jsonlite::fromJSON(
    data_dict_tempest_export_path(),
    simplifyVector = FALSE
  )
  document$tables[[3L]]$columns[[3L]]$values <- "only"
  source <- withr::local_tempfile(fileext = ".json")
  writeLines(canonical_json(document), source, useBytes = TRUE)

  condition <- rlang::catch_cnd(graft_schema(source))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "enum_values")
})

test_that("graft_schema fails closed on malformed display metadata", {
  document <- jsonlite::fromJSON(
    data_dict_tempest_export_path(),
    simplifyVector = FALSE
  )
  document$tables[[2L]]$columns[[6L]]$display <- list("restricted")
  source <- withr::local_tempfile(fileext = ".json")
  writeLines(canonical_json(document), source, useBytes = TRUE)

  condition <- rlang::catch_cnd(graft_schema(source))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "column_display")
  expect_identical(condition$field, "tables[2].columns[6].display")
})

test_that("data-dict contracts govern the unchanged plan and commit path", {
  document <- jsonlite::fromJSON(
    data_dict_personinfo_export_path(),
    simplifyVector = FALSE
  )
  document$tables[[1L]]$columns[[5L]] <- list(
    name = "private_notes",
    description = "Synthetic restricted notes used by the adapter test.",
    display = "restricted",
    type = "string",
    examples = list("Do not display")
  )
  source <- withr::local_tempfile(fileext = ".json")
  writeLines(canonical_json(document), source, useBytes = TRUE)
  schema <- graft_schema(source)
  expect_identical(
    grepl(
      "Do not display",
      canonical_json(schema@manifest),
      fixed = TRUE
    ),
    FALSE
  )
  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))

  records <- list(
    organization = data.frame(
      id = "org:daily-planet",
      name = "Daily Planet"
    ),
    person = data.frame(
      id = "person:clark-kent",
      full_name = "Clark Kent",
      aliases = I(list(c("Superman", "Kal-El"))),
      age = 35,
      private_notes = "Do not display"
    ),
    person_employment = data.frame(
      id = "employment:clark-kent:daily-planet",
      person_id = "person:clark-kent",
      organization_id = "org:daily-planet"
    )
  )
  plan <- graft_plan(
    store,
    records,
    graft_provenance(
      producer = "data-dict-integration-test",
      idempotency_key = "personinfo-v1"
    )
  )

  expect_identical(plan@valid, TRUE)
  expect_equal(nrow(plan@issues), 0L)
  expect_equal(nrow(plan@changes), 3L)
  result <- graft_commit(store, plan)
  expect_equal(sum(result$inserted), 3L)

  person <- graft_get(store, "person:clark-kent", include = character())
  expect_identical(person$class, "person")
  expect_identical(person$record$full_name, "Clark Kent")
  expect_identical("private_notes" %in% names(person$record), FALSE)
  found <- graft_find(store, "Clark", class = "person", limit = 5L)
  expect_equal(nrow(found), 1L)
})

test_that("the shipped data-dict example builds knowledge from an empty store", {
  source <- system.file(
    "extdata",
    "team-directory.data-dict.json",
    package = "graft"
  )
  yaml_source <- system.file(
    "extdata",
    "team-directory.data-dict.yaml",
    package = "graft"
  )
  expect_identical(file.exists(source), TRUE)
  expect_identical(file.exists(yaml_source), TRUE)

  authored <- yaml::read_yaml(yaml_source, eval.expr = FALSE)
  resolved <- jsonlite::fromJSON(source, simplifyVector = FALSE)
  table_names <- function(document) {
    vapply(document$tables, `[[`, character(1), "name")
  }
  column_names <- function(table) {
    vapply(table$columns, `[[`, character(1), "name")
  }
  column_examples <- function(table) {
    lapply(
      table$columns,
      \(column) unname(unlist(column$examples, use.names = FALSE))
    )
  }
  relationship_joins <- function(document) {
    vapply(document$relationships, `[[`, character(1), "join")
  }
  expect_identical(authored$name, resolved$name)
  expect_identical(table_names(authored), table_names(resolved))
  expect_identical(
    lapply(authored$tables, column_names),
    lapply(resolved$tables, column_names)
  )
  expect_identical(
    lapply(authored$tables, column_examples),
    lapply(resolved$tables, column_examples)
  )
  expect_identical(
    relationship_joins(authored),
    relationship_joins(resolved)
  )

  schema <- graft_schema(source)
  expect_identical(schema@name, "team_directory")
  expect_setequal(
    names(schema@classes),
    c("organization", "person", "employment", "GraftDefinition")
  )

  store <- graft_open(schema, path = ":memory:", okf = "disabled")
  withr::defer(graft_close(store))

  invalid <- graft_plan(
    store,
    list(
      person = data.frame(
        id = "person:lois-lane",
        full_name = "Lois Lane",
        job_title = "Reporter"
      ),
      employment = data.frame(
        id = "employment:lois-lane:daily-planet",
        person_id = "person:lois-lane",
        organization_id = "org:missing"
      )
    ),
    graft_provenance(
      producer = "directory-import",
      idempotency_key = "directory-invalid"
    )
  )
  expect_identical(invalid@valid, FALSE)
  expect_in("reference_exists", invalid@issues$rule)

  initial <- list(
    organization = data.frame(
      id = "org:daily-planet",
      name = "Daily Planet"
    ),
    person = data.frame(
      id = "person:lois-lane",
      full_name = "Lois Lane",
      job_title = "Reporter"
    ),
    employment = data.frame(
      id = "employment:lois-lane:daily-planet",
      person_id = "person:lois-lane",
      organization_id = "org:daily-planet"
    )
  )
  plan <- graft_plan(
    store,
    initial,
    graft_provenance(
      producer = "directory-import",
      idempotency_key = "directory-2026-08-01"
    )
  )
  expect_identical(plan@valid, TRUE)
  expect_equal(nrow(plan@changes), 3L)
  graft_commit(store, plan)

  update <- graft_plan(
    store,
    list(
      person = data.frame(
        id = "person:lois-lane",
        full_name = "Lois Lane",
        job_title = "Investigative editor"
      )
    ),
    graft_provenance(
      producer = "directory-import",
      idempotency_key = "directory-2026-08-08"
    )
  )
  expect_identical(update@valid, TRUE)
  graft_commit(store, update)

  current <- graft_get(store, "person:lois-lane")
  expect_identical(current$record$job_title, "Investigative editor")
  expect_equal(nrow(graft_history(store, "person:lois-lane")), 2L)
})

test_that("the Tempest parity fixture exposes the deliberate mapping boundary", {
  schema <- graft_schema(data_dict_tempest_export_path())
  manifest <- schema@manifest

  expect_identical(schema@name, "tempest-artifacts")
  expect_length(schema@classes, 9L)
  expect_identical(manifest$dictionary$mapped$columns_to_slots, 66L)
  expect_identical(manifest$dictionary$mapped$enums, 9L)
  expect_identical(
    manifest$dictionary$mapped$foreign_keys_to_object_references,
    9L
  )
  expect_identical(manifest$classes$source$slots$access_notes$sensitive, TRUE)
  expect_length(manifest$validation_invariants, 0L)
  expect_length(
    manifest$graph_projections$semantic_edges$object_relations,
    0L
  )
  bounds <- unlist(lapply(
    manifest$classes,
    \(class) {
      lapply(
        class$slots,
        \(slot) c(slot$minimum_value, slot$maximum_value)
      )
    }
  ))
  expect_length(bounds, 0L)

  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))
  records <- list(
    entity = data.frame(id = "entity:one", preferred_name = "Entity one"),
    source = data.frame(id = "source:one", access_notes = "restricted"),
    claim = data.frame(
      id = "claim:one",
      statement_text = "A deliberately out-of-assertion-range claim.",
      primary_subject = "entity:one",
      claim_type = "finding",
      confidence = 2,
      valid_from = "2026-02-01T00:00:00",
      valid_to = "2026-01-01T00:00:00"
    ),
    claim_about = data.frame(
      id = "claim-about:one",
      claim_id = "claim:one",
      entity_id = "entity:one"
    ),
    run = data.frame(
      id = c("run:one", "run:two"),
      run_identifier = c("duplicate", "duplicate")
    )
  )
  plan <- graft_plan(
    store,
    records,
    graft_provenance(
      producer = "data-dict-tempest-test",
      idempotency_key = "tempest-boundary"
    )
  )
  expect_identical(plan@valid, TRUE)
  expect_equal(nrow(plan@issues), 0L)
  graft_commit(store, plan)

  retrieved <- graft_get(store, "source:one", include = character())
  expect_identical("access_notes" %in% names(retrieved$record), FALSE)

  bad_enum <- graft_plan(
    store,
    list(
      claim = data.frame(
        id = "claim:one",
        statement_text = "Unknown enum",
        claim_type = "not-a-claim-type"
      )
    ),
    graft_provenance(
      producer = "data-dict-tempest-test",
      idempotency_key = "tempest-bad-enum"
    )
  )
  expect_identical(bad_enum@valid, FALSE)
  expect_in("enum_membership", bad_enum@issues$rule)

  missing_reference <- graft_plan(
    store,
    list(
      claim = data.frame(
        id = "claim:missing-reference",
        statement_text = "Missing reference",
        primary_subject = "entity:missing"
      )
    ),
    graft_provenance(
      producer = "data-dict-tempest-test",
      idempotency_key = "tempest-missing-reference"
    )
  )
  expect_identical(missing_reference@valid, FALSE)
  expect_in("reference_exists", missing_reference@issues$rule)
})

test_that("graft_schema routes data-dict YAML through the optional CLI bridge", {
  source <- withr::local_tempfile(pattern = "data-dict-", fileext = ".yaml")
  writeLines(c("$version: 0.1.0", "name: personinfo", "tables: []"), source)
  document <- jsonlite::fromJSON(
    data_dict_personinfo_export_path(),
    simplifyVector = FALSE
  )
  local_mocked_bindings(
    read_data_dict_contract = function(path) {
      list(
        document = document,
        source_digest = data_dict_source_snapshot(path)$digest,
        provider = list(
          name = "data-dict",
          export_format_version = "0.1.0",
          source_spec_version = "0.1.0",
          cli_version = "0.0.1",
          cli_digest = graft_sha256("mock-data-dict"),
          revision = "d794c961",
          source_path = normalizePath(path, winslash = "/"),
          source_format = "yaml"
        )
      )
    }
  )

  schema <- graft_schema(source)

  expect_identical(schema@name, "personinfo")
  expect_identical(
    schema@manifest$compiler$provider$source_format,
    "yaml"
  )
  expect_identical(
    "source_path" %in% names(schema@manifest$compiler$provider),
    FALSE
  )
  expect_identical(
    schema@manifest$compiler$provider$cli_digest,
    graft_sha256("mock-data-dict")
  )
  expect_identical(
    schema@manifest$dictionary$provider,
    schema@manifest$compiler$provider
  )
})
