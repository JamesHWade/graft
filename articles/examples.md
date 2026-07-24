# Examples

A useful schema does more than name columns. It distinguishes things
that should not be conflated and makes important relationships explicit.

This page contains two small examples:

- a chemistry model for a molecule, its stereoisomers, and a racemic
  mixture; and
- a biology model connecting a study, a biosample, and a sequencing
  process.

Both are ordinary LinkML schemas. Neither imports graft’s core schema or
uses graft annotations. See [Use a LinkML schema with
graft](https://jameshwade.github.io/graft/articles/linkml-schema.md) for
a slower introduction to compiling a schema.

The examples are deliberately smaller than the models that inspired
them. They preserve the useful modeling pattern without claiming
conformance to the full upstream standard.

## Chemistry: distinguish a molecule from its forms

[CHEMROF](https://chemkg.github.io/chemrof/home/) is a LinkML model for
chemical entities, mixtures, and related concepts. One of its examples
models thalidomide as two enantiomers and a racemic mixture.

That distinction matters. A name such as “thalidomide” is not enough to
tell us whether a record means the chirality-agnostic molecule, one
stereoisomer, or a mixture.

The example schema uses inheritance and typed references:

``` yaml
classes:
  ChemicalEntity:
    abstract: true
    attributes:
      id:
        identifier: true
        required: true
        range: uriorcurie
      name:
        required: true

  Enantiomer:
    is_a: Molecule
    attributes:
      chirality:
        range: ChiralityEnum
        required: true
      chirality_agnostic_form:
        range: Molecule
        required: true
        inlined: false

  RacemicMixture:
    is_a: ChemicalEntity
    attributes:
      has_left_enantiomer:
        range: Enantiomer
        required: true
        inlined: false
      has_right_enantiomer:
        range: Enantiomer
        required: true
        inlined: false
```

The [complete chemistry
schema](https://github.com/JamesHWade/graft/blob/main/inst/extdata/chemistry.linkml.yaml)
also declares molecular formulae, aliases, semantic mappings, and an
enum for chirality.

Load the compiled manifest and inspect the concrete classes:

``` r

library(graft)

chemistry_schema <- kg_schema(system.file(
  "extdata",
  "chemistry.graft.json",
  package = "graft"
))

kg_classes(chemistry_schema)
#>            class role statement_shape           table id_policy
#> 1     Enantiomer node            <NA>      enantiomer   require
#> 2       Molecule node            <NA>        molecule   require
#> 3 RacemicMixture node            <NA> racemic_mixture   require
kg_enums(chemistry_schema)
#>            enum value meaning                description
#> 1 ChiralityEnum  left    <NA>  Left-handed stereoisomer.
#> 2 ChiralityEnum right    <NA> Right-handed stereoisomer.
```

The data use CURIEs as their identifiers. References contain the
identifier of the target record.

``` r

chemistry_records <- list(
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
```

Write all three classes in one batch. graft checks the references
against both the existing store and the other records staged in the
batch.

``` r

chemistry_store <- suppressMessages(
  kg_connect_duckdb(chemistry_schema, ":memory:")
)
kg_init(chemistry_store)

kg_ingest(
  chemistry_store,
  kg_batch(
    producer = "chemistry-example",
    idempotency_key = "thalidomide-v1"
  ),
  chemistry_records
)
#> <kg_ingest_result> committed graft:01KY8X3J7TR1Z70V06BN89156B
#>   inserted: 4
#>   updated:  0
#>   matched:  0
#>   observed: 4
```

The mixture can then be retrieved without flattening away the
distinction between the molecule and its stereoisomers:

``` r

mixture <- kg_get(chemistry_store, "CHEBI:9513")

mixture$record[c("id", "name")]
#> $id
#> [1] "CHEBI:9513"
#> 
#> $name
#> [1] "racemic thalidomide"
mixture$record[c(
  "has_left_enantiomer",
  "has_right_enantiomer",
  "chirality_agnostic_form"
)]
#> $has_left_enantiomer
#> [1] "chemistry:S-thalidomide"
#> 
#> $has_right_enantiomer
#> [1] "chemistry:R-thalidomide"
#> 
#> $chirality_agnostic_form
#> [1] "chemistry:thalidomide"
```

This pattern also works for salts, isotopes, mixtures, reaction
participants, or any other case where chemistry-specific identity
matters.

## Biology: connect samples to the work performed on them

The [National Microbiome Data Collaborative
schema](https://microbiomedata.github.io/nmdc-schema/) uses LinkML to
describe environmental omics data. Its model separates studies,
biosamples, data generation, workflow executions, and data objects.

The smaller schema here keeps three of those ideas:

``` yaml
classes:
  Study:
    is_a: NamedThing

  Biosample:
    is_a: NamedThing
    attributes:
      associated_studies:
        range: Study
        required: true
        multivalued: true
        inlined: false
      ecosystem:
      collection_site:

  NucleotideSequencing:
    is_a: DataGeneration
    attributes:
      has_input:
        range: Biosample
        required: true
        multivalued: true
        inlined: false
      analyte_category:
        range: AnalyteCategoryEnum
        required: true
```

The [complete biology
schema](https://github.com/JamesHWade/graft/blob/main/inst/extdata/biology.linkml.yaml)
adds semantic mappings, coordinates, instrument details, and a
controlled vocabulary for the analyte.

``` r

biology_schema <- kg_schema(system.file(
  "extdata",
  "biology.graft.json",
  package = "graft"
))

kg_classes(biology_schema)
#>                  class role statement_shape                 table id_policy
#> 1            Biosample node            <NA>             biosample   require
#> 2 NucleotideSequencing node            <NA> nucleotide_sequencing   require
#> 3                Study node            <NA>                 study   require
kg_slots(biology_schema, "Biosample")
#>        class               slot      range relational_type required multivalued
#> 1  Biosample  alternative_names     string         VARCHAR    FALSE        TRUE
#> 2  Biosample associated_studies      Study         VARCHAR     TRUE        TRUE
#> 3  Biosample    collection_site     string         VARCHAR    FALSE       FALSE
#> 4  Biosample         created_at   datetime       TIMESTAMP    FALSE       FALSE
#> 5  Biosample        description     string         VARCHAR    FALSE       FALSE
#> 6  Biosample          ecosystem     string         VARCHAR    FALSE       FALSE
#> 7  Biosample                 id uriorcurie         VARCHAR     TRUE       FALSE
#> 8  Biosample           latitude      float          DOUBLE    FALSE       FALSE
#> 9  Biosample          longitude      float          DOUBLE    FALSE       FALSE
#> 10 Biosample               name     string         VARCHAR     TRUE       FALSE
#> 11 Biosample         updated_at   datetime       TIMESTAMP    FALSE       FALSE
#>    identifier object_reference enum          column
#> 1       FALSE            FALSE <NA>            <NA>
#> 2       FALSE             TRUE <NA>            <NA>
#> 3       FALSE            FALSE <NA> collection_site
#> 4       FALSE            FALSE <NA>      created_at
#> 5       FALSE            FALSE <NA>     description
#> 6       FALSE            FALSE <NA>       ecosystem
#> 7        TRUE            FALSE <NA>              id
#> 8       FALSE            FALSE <NA>        latitude
#> 9       FALSE            FALSE <NA>       longitude
#> 10      FALSE            FALSE <NA>            name
#> 11      FALSE            FALSE <NA>      updated_at
```

The records make the provenance chain explicit: the sequencing process
belongs to a study and takes a particular biosample as input.

``` r

biology_records <- list(
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
```

``` r

biology_store <- suppressMessages(
  kg_connect_duckdb(biology_schema, ":memory:")
)
kg_init(biology_store)

kg_ingest(
  biology_store,
  kg_batch(
    producer = "biology-example",
    idempotency_key = "soil-v1"
  ),
  biology_records
)
#> <kg_ingest_result> committed graft:01KY8X3KMRTBDHJ9WCGDCA94Z4
#>   inserted: 3
#>   updated:  0
#>   matched:  0
#>   observed: 3
```

The tabular and hydrated interfaces answer different questions:

``` r

kg_records(biology_store, "Biosample") |>
  dplyr::select(id, name, ecosystem, collection_site) |>
  dplyr::collect()
#> # A tibble: 1 × 4
#>   id          name                ecosystem     collection_site    
#>   <chr>       <chr>               <chr>         <chr>              
#> 1 nmdc:bsm-11 Forest soil core 11 Environmental Example forest plot

sequencing <- kg_get(biology_store, "nmdc:dg-11")
sequencing$record[c(
  "name",
  "analyte_category",
  "has_input",
  "associated_studies"
)]
#> $name
#> [1] "Soil metagenome sequencing"
#> 
#> $analyte_category
#> [1] "metagenome"
#> 
#> $has_input
#> [1] "nmdc:bsm-11"
#> 
#> $associated_studies
#> [1] "nmdc:sty-11"
```

The same pattern can connect specimens to assays, genes to phenotypes,
or organisms to observations. LinkML supplies the domain vocabulary and
constraints; graft supplies the local storage and retrieval layer.

## Use the upstream model when it fits

These examples are adaptations, not replacements for CHEMROF or NMDC. A
production project should first ask whether an established model already
describes its data.

Compile the upstream schema directly when it uses the LinkML constructs
graft supports and its classes match the records you need. Use a smaller
schema when you need only a well-defined subset, and retain upstream
`class_uri`, `slot_uri`, and identifier mappings so that the
relationship remains visible.

The official [LinkML examples
page](https://linkml.io/linkml/examples.html) also points to Biolink,
NMDC, and other production models. The [LinkML Schema
Registry](https://linkml.io/linkml-registry/registry/) is useful when
looking for an existing model in another domain.
