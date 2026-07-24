# Getting started with graft

An R workflow can end with well-formed data frames and still leave
important questions unresolved. Is this the same material seen in an
earlier run? Which source supports a claim? Is a relationship stated by
the source or inferred by the application? What can another analyst or
an AI tool safely retrieve?

graft records those decisions in one versioned contract and applies the
contract whenever data are written or read. It covers:

- which fields identify the same record across runs;
- which fields are required and how they are validated;
- whether a statement is narrative or semantic;
- how claims, sources, and evidence are related; and
- which relationships are available as graph projections.

With the contract in place, repeated workflow runs can recognize the
same record, claims remain separate from adjudicated truth, and
retrieval can return the exact source location stored with an assertion.

graft expresses the contract in [LinkML](https://linkml.io/) and
compiles it into a portable JSON manifest. At runtime, the manifest
governs identity, validation, storage, and retrieval.

This guide uses the materials schema included with the package. It
creates an in-memory store, writes a material and a source, adds a claim
and its evidence, and then queries the result.

## How the pieces fit together

From a package user’s perspective, the main workflow is:

> domain contract -\> validated workflow results -\> connected records
> -\> bounded R retrieval

Each part has one job:

1.  **Describe the domain.** Use ordinary LinkML classes and slots for
    the records your workflow produces. Add graft’s optional roles when
    you need explicit claims, sources, evidence, or graph behavior.
2.  **Compile the runtime contract.** The generated `.graft.json`
    manifest resolves fields, identity rules, validation, relationships,
    and schema fingerprints. Commit it with your project.
3.  **Ingest workflow results.** graft validates related data frames
    atomically, reconciles declared identifiers, and records the
    producer and replay boundary.
4.  **Retrieve records with context.** Read one class lazily with dbplyr
    or use bounded functions to inspect records, claims, evidence, and
    graph neighborhoods.

The current backend is embedded DuckDB. That keeps stores local,
portable, and available to familiar DBI and dbplyr workflows without
making the backend the domain model.

Python and `linkml-runtime` are used only for step 2. Loading an
existing manifest and performing normal storage or retrieval both run
entirely in R.

## Installation

graft is currently available from GitHub:

``` r

pak::pak("JamesHWade/graft")
```

## Start from a compiled contract

``` r

library(graft)
```

The package includes a small materials contract for this guide. Loading
the compiled manifest does not initialize Python:

``` r

manifest <- system.file(
  "extdata",
  "materials.graft.json",
  package = "graft"
)
schema <- kg_schema(manifest)
schema
#> <kg_schema> materials 0.1.0
#>   classes:    5
#>   relations:  1
#>   structural: sha256:2f89cfc254e22a342a36ae87e438164fa714de11c712d57e5d7be25bfa00e145
```

Inspect the contract before creating a store:

``` r

kg_classes(schema)
#>         class      role statement_shape       table     id_policy
#> 1       Claim statement       narrative       claim          mint
#> 2    Evidence  evidence            <NA>    evidence          mint
#> 3    Material      node            <NA>    material resolve_exact
#> 4 Measurement statement        semantic measurement          mint
#> 5      Source    source            <NA>      source resolve_exact
kg_slots(schema, "Claim")
#>    class            slot             range relational_type required multivalued
#> 1  Claim           about         GraftNode         VARCHAR     TRUE        TRUE
#> 2  Claim     asserted_at          datetime       TIMESTAMP    FALSE       FALSE
#> 3  Claim      claim_type         ClaimType         VARCHAR    FALSE       FALSE
#> 4  Claim      confidence             float          DOUBLE    FALSE       FALSE
#> 5  Claim      created_at          datetime       TIMESTAMP    FALSE       FALSE
#> 6  Claim              id        uriorcurie         VARCHAR     TRUE       FALSE
#> 7  Claim        polarity StatementPolarity         VARCHAR    FALSE       FALSE
#> 8  Claim primary_subject         GraftNode         VARCHAR    FALSE       FALSE
#> 9  Claim  statement_text            string         VARCHAR     TRUE       FALSE
#> 10 Claim          status   StatementStatus         VARCHAR    FALSE       FALSE
#> 11 Claim   superseded_by    GraftStatement         VARCHAR    FALSE       FALSE
#> 12 Claim      updated_at          datetime       TIMESTAMP    FALSE       FALSE
#> 13 Claim      valid_from          datetime       TIMESTAMP    FALSE       FALSE
#> 14 Claim        valid_to          datetime       TIMESTAMP    FALSE       FALSE
#>    identifier object_reference              enum          column
#> 1       FALSE             TRUE              <NA>            <NA>
#> 2       FALSE            FALSE              <NA>     asserted_at
#> 3       FALSE            FALSE         ClaimType      claim_type
#> 4       FALSE            FALSE              <NA>      confidence
#> 5       FALSE            FALSE              <NA>      created_at
#> 6        TRUE            FALSE              <NA>              id
#> 7       FALSE            FALSE StatementPolarity        polarity
#> 8       FALSE             TRUE              <NA> primary_subject
#> 9       FALSE            FALSE              <NA>  statement_text
#> 10      FALSE            FALSE   StatementStatus          status
#> 11      FALSE             TRUE              <NA>   superseded_by
#> 12      FALSE            FALSE              <NA>      updated_at
#> 13      FALSE            FALSE              <NA>      valid_from
#> 14      FALSE            FALSE              <NA>        valid_to
```

The `role` and `statement_shape` columns are important. They let graft
treat domain-specific classes consistently without pretending that every
record is the same kind of thing:

- nodes are the subjects and objects a workflow reasons about;
- narrative statements preserve source-faithful language;
- semantic statements express an intentional subject-predicate-object
  assertion;
- sources describe where information came from;
- evidence connects a statement to a stored source and locator.

## Create a store

For exploration, use an in-memory DuckDB database. For a durable store,
replace `":memory:"` with a file path.

``` r

store <- kg_connect_duckdb(schema, ":memory:")
#> duckdb is keeping downloaded extensions in a temporary directory:
#> ℹ /tmp/RtmpsqJ6uE/duckdb/extensions
#> This is removed when the R session ends, so extensions are re-downloaded each session.
#> ℹ To keep them, point `options(duckdb.extension_directory =)` or the `DUCKDB_EXTENSION_DIRECTORY` environment variable at a permanent path.
kg_init(store)
store
#> <kg_store> DuckDB initialized (read-write)
#>   path:       :memory:
#>   structural: sha256:2f89cfc254e22a342a36ae87e438164fa714de11c712d57e5d7be25bfa00e145
```

[`kg_init()`](https://jameshwade.github.io/graft/reference/kg_init.md)
creates the tables and graph views declared by the manifest, plus
graft’s private metadata tables. Calling it again is safe. If an
existing store was initialized with a structurally different manifest,
graft reports a schema mismatch rather than silently changing the
meaning of its data.

## Ingest records with provenance

Ingestion happens in atomic batches. A batch identifies the producer and
provides an optional idempotency key, so rerunning the same stage does
not duplicate its observations.

First ingest one material and one source:

``` r

foundations <- list(
  Material = data.frame(
    preferred_name = "Linear low-density polyethylene (LLDPE)",
    description = "A polyethylene with controlled short-chain branching.",
    cas_number = "9002-88-4"
  ),
  Source = data.frame(
    uri = "https://example.org/lldpe-study",
    title = "Controlled DSC study of LLDPE crystallinity",
    doi = "10.1000/lldpe.dsc"
  )
)

kg_ingest(
  store,
  kg_batch(
    producer = "getting-started",
    source_run_id = "materials-demo",
    idempotency_key = "foundations-v1"
  ),
  foundations
)
#> <kg_ingest_result> committed graft:01KY8X3R8XR1Z70V06BN89156B
#>   inserted: 2
#>   updated:  0
#>   matched:  0
#>   observed: 2
```

graft minted internal IDs and registered the schema-declared external
identifiers. Exact lookup resolves normalized external values back to
the stable records:

``` r

material_id <- kg_lookup(
  store,
  namespace = "cas",
  value = "CAS: 9002-88-4"
)$record_id[[1]]

source_id <- kg_lookup(
  store,
  namespace = "doi",
  value = "https://doi.org/10.1000/LLDPE.DSC"
)$record_id[[1]]
```

Now add a claim about the material. A multivalued LinkML slot, such as
`about`, is represented as a list-column:

``` r

kg_write(
  store,
  kg_batch(
    producer = "getting-started",
    source_run_id = "materials-demo",
    idempotency_key = "claim-v1"
  ),
  class = "Claim",
  records = data.frame(
    statement_text = paste(
      "A controlled DSC experiment measured 37% crystallinity",
      "for the LLDPE sample."
    ),
    primary_subject = material_id,
    claim_type = "finding",
    polarity = "positive",
    confidence = 0.95,
    status = "active",
    about = I(list(material_id))
  )
)
#> <kg_ingest_result> committed graft:01KY8X3SAYQ2GY08F99AMH9TQ1
#>   inserted: 1
#>   updated:  0
#>   matched:  0
#>   observed: 1

claim_id <- kg_find(
  store,
  "crystallinity",
  class = "Claim",
  limit = 1
)$id[[1]]
```

Finally, connect the claim to the exact source passage:

``` r

kg_write(
  store,
  kg_batch(
    producer = "getting-started",
    source_run_id = "materials-demo",
    idempotency_key = "evidence-v1"
  ),
  class = "Evidence",
  records = data.frame(
    statement_id = claim_id,
    source_id = source_id,
    support_type = "supports",
    locator_type = "other",
    locator_value = "table 1",
    page_start = 5L,
    page_end = 5L,
    excerpt = "Crystallinity (%) for the LLDPE sample: 37."
  )
)
#> <kg_ingest_result> committed graft:01KY8X3T9Q92H6D99E1M5Y9W65
#>   inserted: 1
#>   updated:  0
#>   matched:  0
#>   observed: 1
```

These writes are separate because the example lets graft mint each ID
before a later record refers to it. Producers that already have stable
graft IDs can submit all related classes in one atomic
[`kg_ingest()`](https://jameshwade.github.io/graft/reference/kg_ingest.md)
call.

## Retrieve an answer and its evidence

Search is useful for discovery:

``` r

kg_find(store, "LLDPE", limit = 5)
#>                                 id    class
#> 1 graft:01KY8X3RNM78J8TW5CCRM2CHPK   Source
#> 2 graft:01KY8X3RN8C500CHZ4PA036PQ1 Material
#> 3 graft:01KY8X3SQDXYMNMFJVDDVKRXM5    Claim
#>                                                                          label
#> 1                                  Controlled DSC study of LLDPE crystallinity
#> 2                                      Linear low-density polyethylene (LLDPE)
#> 3 A controlled DSC experiment measured 37% crystallinity for the LLDPE sample.
#>   score
#> 1     6
#> 2     5
#> 3     3
```

Hydration starts from one stable ID and returns bounded related records:

``` r

material <- kg_get(store, material_id)
material
#> <kg_record> Material graft:01KY8X3RN8C500CHZ4PA036PQ1
#>   identifiers: 1
#>   claims: 1
#>   evidence: 1

material$record[c("preferred_name", "cas_number")]
#> $preferred_name
#> [1] "Linear low-density polyethylene (LLDPE)"
#> 
#> $cas_number
#> [1] "9002-88-4"
```

Claims remain assertions rather than being collapsed into a single
truth. Their status, polarity, qualifiers, and evidence stay available
for inspection:

``` r

claims <- kg_claims(store, material_id)
claims[c("statement_text", "confidence", "status")]
#>                                                                 statement_text
#> 1 A controlled DSC experiment measured 37% crystallinity for the LLDPE sample.
#>   confidence status
#> 1       0.95 active

evidence <- kg_evidence(store, claim_id)
evidence[c(
  "support_type",
  "source_title",
  "locator_value",
  "excerpt"
)]
#>   support_type                                source_title locator_value
#> 1     supports Controlled DSC study of LLDPE crystallinity       table 1
#>                                       excerpt
#> 1 Crystallinity (%) for the LLDPE sample: 37.
```

This distinction is deliberate. A narrative claim records what a source
says. A semantic statement records an intentional normalized assertion.
Evidence can support or contradict either statement shape, and graft can
return competing claims without adjudicating them on the user’s behalf.

## Choose the right retrieval surface

graft offers different interfaces for different jobs:

| Need | Interface | Collection behavior |
|----|----|----|
| Work with one class using dplyr | [`kg_records()`](https://jameshwade.github.io/graft/reference/kg_records.md) | Lazy |
| Discover records by declared text fields | [`kg_find()`](https://jameshwade.github.io/graft/reference/kg_find.md) | Bounded |
| Resolve an external identifier exactly | [`kg_lookup()`](https://jameshwade.github.io/graft/reference/kg_lookup.md) | Bounded |
| Hydrate one record and related knowledge | [`kg_get()`](https://jameshwade.github.io/graft/reference/kg_get.md) | Bounded |
| Inspect claims and stored citations | [`kg_claims()`](https://jameshwade.github.io/graft/reference/kg_claims.md), [`kg_evidence()`](https://jameshwade.github.io/graft/reference/kg_evidence.md) | Bounded |
| Run a validated structured query | [`kg_select()`](https://jameshwade.github.io/graft/reference/kg_select.md) | Bounded |
| Explore a graph neighborhood | [`kg_neighbors()`](https://jameshwade.github.io/graft/reference/kg_neighbors.md) | Bounded |

For example,
[`kg_records()`](https://jameshwade.github.io/graft/reference/kg_records.md)
returns a lazy dbplyr table:

``` r

kg_records(store, "Claim") |>
  dplyr::select(id, statement_text, confidence) |>
  dplyr::collect()
#> # A tibble: 1 × 3
#>   id                               statement_text                     confidence
#>   <chr>                            <chr>                                   <dbl>
#> 1 graft:01KY8X3SQDXYMNMFJVDDVKRXM5 A controlled DSC experiment measu…       0.95
```

[`kg_select()`](https://jameshwade.github.io/graft/reference/kg_select.md)
is the safer collected interface when a caller should choose fields and
filters but must not provide SQL:

``` r

kg_select(
  store,
  class = "Claim",
  fields = c("id", "statement_text", "confidence"),
  filters = list(list(
    field = "confidence",
    operator = "gte",
    value = 0.9
  )),
  limit = 10
)
#>                                 id
#> 1 graft:01KY8X3SQDXYMNMFJVDDVKRXM5
#>                                                                 statement_text
#> 1 A controlled DSC experiment measured 37% crystallinity for the LLDPE sample.
#>   confidence
#> 1       0.95
```

## Use graft with ellmer

If the `ellmer` package is installed,
[`kg_tools()`](https://jameshwade.github.io/graft/reference/kg_tools.md)
creates six read-only tools that capture one initialized store:

``` r

chat <- ellmer::chat_anthropic()
chat$set_tools(kg_tools(store))
```

The tools call the same query functions shown above. They do not accept
SQL, file paths, URLs, or network options. Each result reports its
limit, whether it was truncated, and the store’s schema digest.

[`kg_tools()`](https://jameshwade.github.io/graft/reference/kg_tools.md)
does not validate model output. It gives a model read-only access to
records and evidence that are already present in the store.

## Bring your own domain

The [LinkML schema
article](https://jameshwade.github.io/graft/articles/linkml-schema.md)
starts with an ordinary PersonInfo-style schema. It compiles without
graft annotations or an import of graft’s core schema.

The installed materials example shows the optional enriched form:

``` r

system.file(
  "extdata",
  "materials.linkml.yaml",
  package = "graft"
)
#> [1] "/home/runner/work/_temp/Library/graft/extdata/materials.linkml.yaml"
```

Extend graft’s core roles only when the domain needs package-specific
behavior for claims, evidence, sources, mentions, or graph edges:

- `GraftNode`
- `GraftEdge`
- `GraftNarrativeStatement`
- `GraftSemanticStatement`
- `GraftSource`
- `GraftEvidence`
- `GraftMention`
- `GraftMetadata`

Annotations can then declare identity policies, external identifier
namespaces, search fields, label fields, origin keys, and semantic
qualifiers. Compile the schema once:

``` r

kg_compile_schema(
  "my-domain.linkml.yaml",
  "my-domain.graft.json"
)
```

Commit both the source schema and compiled manifest. Application and
production environments can then load the manifest without Python:

``` r

schema <- kg_schema("my-domain.graft.json")
store <- kg_connect_duckdb(schema, "knowledge.duckdb")
kg_init(store)
```

## When to use graft

Use graft when a project needs to preserve record identity, claims,
sources, and evidence across runs while keeping the data available
through R, DBI, and dbplyr.

graft does not design the LinkML schema, collect source material,
provide vector similarity search, or replace a general-purpose graph
database. It manages the boundary between schema-defined records and
their representation in DuckDB.
