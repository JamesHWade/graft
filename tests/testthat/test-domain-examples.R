test_that("chemistry example compiles and stores stereoisomer relationships", {
  skip_if_no_linkml_runtime()
  schema <- kg_compile_schema(
    example_schema_path("chemistry"),
    withr::local_tempfile(fileext = ".graft.json")
  )
  store <- kg_connect_duckdb(schema, ":memory:")
  withr::defer(kg_disconnect(store))
  kg_init(store)

  kg_ingest(
    store,
    kg_batch("chemistry-example", idempotency_key = "thalidomide-v1"),
    list(
      Molecule = data.frame(
        id = "chemistry:thalidomide",
        name = "thalidomide",
        molecular_formula = "C13H10N2O4"
      ),
      Enantiomer = data.frame(
        id = c("chemistry:S-thalidomide", "chemistry:R-thalidomide"),
        name = c("S-thalidomide", "R-thalidomide"),
        molecular_formula = c("C13H10N2O4", "C13H10N2O4"),
        chirality = c("left", "right"),
        chirality_agnostic_form = c(
          "chemistry:thalidomide",
          "chemistry:thalidomide"
        )
      ),
      RacemicMixture = data.frame(
        id = "CHEBI:9513",
        name = "racemic thalidomide",
        aliases = I(list(c("thalidomide", "thalidomide racemate"))),
        has_left_enantiomer = "chemistry:S-thalidomide",
        has_right_enantiomer = "chemistry:R-thalidomide",
        chirality_agnostic_form = "chemistry:thalidomide"
      )
    )
  )

  mixture <- kg_get(store, "CHEBI:9513")

  expect_identical(mixture$class, "RacemicMixture")
  expect_identical(
    mixture$record$has_left_enantiomer[[1]],
    "chemistry:S-thalidomide"
  )
  expect_setequal(
    mixture$record$aliases,
    c("thalidomide", "thalidomide racemate")
  )
})

test_that("biology example connects studies, biosamples, and sequencing", {
  skip_if_no_linkml_runtime()
  schema <- kg_compile_schema(
    example_schema_path("biology"),
    withr::local_tempfile(fileext = ".graft.json")
  )
  store <- kg_connect_duckdb(schema, ":memory:")
  withr::defer(kg_disconnect(store))
  kg_init(store)

  kg_ingest(
    store,
    kg_batch("biology-example", idempotency_key = "soil-v1"),
    list(
      Study = data.frame(
        id = "nmdc:sty-11",
        name = "Forest soil carbon study",
        objective = "Relate soil conditions to microbial carbon cycling.",
        ecosystem = "Environmental"
      ),
      Biosample = data.frame(
        id = "nmdc:bsm-11",
        name = "Forest soil core 11",
        associated_studies = I(list("nmdc:sty-11")),
        ecosystem = "Environmental",
        collection_site = "Example forest plot",
        latitude = 44.57,
        longitude = -85.61
      ),
      NucleotideSequencing = data.frame(
        id = "nmdc:dg-11",
        name = "Soil metagenome sequencing",
        associated_studies = I(list("nmdc:sty-11")),
        has_input = I(list("nmdc:bsm-11")),
        analyte_category = "metagenome",
        instrument_name = "Illumina NovaSeq",
        processing_institution = "Example sequencing center"
      )
    )
  )

  sequencing <- kg_get(store, "nmdc:dg-11")

  expect_identical(sequencing$class, "NucleotideSequencing")
  expect_identical(sequencing$record$has_input, "nmdc:bsm-11")
  expect_identical(
    kg_find(store, "soil core", class = "Biosample", limit = 5)$id,
    "nmdc:bsm-11"
  )
})
