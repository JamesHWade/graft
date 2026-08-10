# Contract compiler details

This article is the reference for building Graft contracts. The
introductory guides use committed artifacts so that their examples run
without Rust or Python.

## Choose the input boundary

[`graft_schema()`](https://jameshwade.github.io/graft/reference/graft_schema.md)
accepts four useful inputs:

| Input | Compiler needed during use | Result |
|----|----|----|
| compiled `.graft.json` | none | loads the canonical contract |
| resolved data-dict `export-spec` JSON | R only | runs the Graft data-dict adapter |
| data-dict YAML | `data-dict` executable | resolves YAML, then runs the adapter |
| LinkML YAML | Python and `linkml-runtime` | resolves imports and compiles LinkML |

Use `output` to retain a compiled manifest:

``` r

library(graft)

schema <- graft_schema(
  "source-contract.yaml",
  output = "source-contract.graft.json"
)
```

Without `output`, graft retains the compiled manifest in a temporary
file for the lifetime of the R session.

## Build from data-dict YAML

YAML compilation delegates the evolving source syntax to data-dict.
Install and pin the CLI in the environment that builds contract
artifacts. The version used for the bundled example is pinned by
revision:

``` bash
cargo install \
  --git https://github.com/tidyverse/data-dict \
  --rev d794c9616f7803199432e9b31b519216aa78d1b0 \
  data-dict-cli
```

graft finds `data-dict` on `PATH`. An R option or environment variable
can select another executable:

``` r

options(
  graft.data_dict_cli = "/absolute/path/to/data-dict",
  graft.data_dict_revision =
    "d794c9616f7803199432e9b31b519216aa78d1b0"
)
```

The equivalent environment variables are `GRAFT_DATA_DICT_CLI` and
`GRAFT_DATA_DICT_REVISION`. The revision is caller-supplied provenance;
graft does not infer or verify a Git commit from the executable.

For YAML input, graft:

1.  reads the source bytes once into a private snapshot;
2.  parses the snapshot with YAML expression evaluation disabled;
3.  checks that every declared column has a type;
4.  hashes the selected executable;
5.  runs `data-dict export-spec` against the snapshot;
6.  verifies that the executable digest has not changed;
7.  records `data-dict --version`; and
8.  verifies the executable digest again.

Compilation fails if the executable changes during those steps. The
source digest, preflight, and resolved output therefore refer to the
same captured bytes. The compiled manifest records the observed CLI
version and digest, optional caller-supplied revision, source-spec
version, export-format version, and adapter version. It does not publish
the configured executable path, input path, or private snapshot path.

graft runs only `export-spec`. Run data-dict’s metadata and data
validation commands separately when they are part of the source-data
workflow.

## Build from resolved data-dict JSON

Resolve YAML once when contract builds need the upstream source
semantics but runtime environments should remain R-only:

``` bash
data-dict export-spec data-dict.yaml > data-dict.export.json
```

``` r

schema <- graft_schema(
  "data-dict.export.json",
  output = "data-dict.graft.json"
)
```

Resolved JSON is trusted build input. Its top-level `$version` is the
resolved export-format version, not proof of the YAML source-spec
version or of the program that generated it. Resolved JSON therefore has
no observed CLI version or executable digest.

The adapter rejects duplicate object keys, unknown provider fields,
malformed version and constraint containers, unsupported export-format
versions, and `export-data` row payloads or profiles. It also rejects
JSON number tokens that would lose integer exactness above `2^53 - 1`,
overflow to a non-finite R value, or underflow from a lexically nonzero
value to zero. Identifiers and exact codes belong in quoted strings.

## Treat the manifest as public metadata

The data-dict manifest retains names, labels, descriptions, details,
glossary entries, enum values, units, assertions, relationships, joins,
and sensitivity declarations. Do not put secrets in those fields.

Before publishing the manifest, the adapter removes column examples and
ranges, dataset and table origins, and table source locators. The raw
input still affects source and build digests. Those digests do not
reveal a removed value directly, but they permit equality tests and
offline guessing of low-entropy values. Redaction is not a secrecy
boundary.

`display: restricted` marks accepted record values as sensitive for
retrieval. It does not hide the schema description. Primary IDs remain
public operational keys and cannot be restricted.

## Understand the data-dict execution limits

The adapter deliberately executes less than the full data-dict language:

- representative ranges and assertion text remain documentation;
- non-primary uniqueness and relationship cardinality are not enforced;
- conflicts, range joins, join aliases, and multi-column joins are not
  executed;
- source row profiles and `export-data` observations cannot enter the
  contract;
- table origins and source locators are redacted without being
  validated;
- numeric measures use Graft’s R-facing double representation rather
  than data-dict’s Parquet-metadata validation rules; and
- foreign keys validate target IDs but do not become graph traversal
  edges.

Scalar values and one-level lists of scalar values are supported.
Structs, nested lists, and list-valued foreign keys are rejected.
`number(id)` and `list(number(id))` are rejected because numeric codes
cannot be lowered to text without changing equality.

Datetime contracts have an explicit boundary. With no `time_zone`,
character values must carry an RFC 3339 `Z` or `+/-HH:MM` offset. With
`time_zone: UTC`, character values must be zoneless and are interpreted
as UTC. Both forms need `T`, seconds, and no more than six fractional
digits. `POSIXt` values are accepted as resolved instants; `Date`,
`time_zone: naive`, and named zones such as `America/Detroit` are
rejected for these contracts.

Graft also applies its own missing-value rules. Empty required strings,
empty required lists, and missing elements inside collections are
invalid. Optional scalar foreign keys normalize empty or whitespace-only
strings to missing. These rules can be stricter than container-nullness
checks in data-dict.

The mapping report in `schema@manifest$dictionary` names mapped
behavior, defaults, and known semantics that Graft does not enforce. It
is a review aid, not an exhaustive equivalence proof.

## Build from LinkML

LinkML is the richer source when classes need inheritance and ontology
URIs, or when relationships need Graft’s node, edge, statement,
evidence, source, and mention roles.

``` r

schema <- graft_schema(
  "domain.linkml.yaml",
  output = "domain.graft.json"
)
```

The compiler uses `reticulate` and declares `linkml-runtime>=1.9,<2`. It
resolves the import closure and records the compiler, Python, and LinkML
runtime versions along with source-file digests. Load the resulting
`.graft.json` in an R-only runtime:

``` r

schema <- graft_schema("domain.graft.json")
```

An ordinary LinkML schema is sufficient. It does not have to import
Graft’s base schema unless it uses Graft-specific record roles and
invariants.

The compiler follows a strict profile so that unsupported source
semantics do not appear to remain active:

- direct `is_a` inheritance and class-local `slot_usage` overrides are
  supported;
- class mixins are rejected because their flattened ancestry cannot be
  checked as one parent chain;
- custom LinkML types are rejected rather than losing inherited
  constraints;
- class rules and unique keys are rejected;
- unsupported slot equality, cardinality, expression, default, unit,
  member, identifier-prefix, and structured-pattern fields are rejected;
- unsupported schema bindings and slot-name constraints are rejected;
  and
- enum identity, enum inheritance, and permissible-value inheritance are
  rejected.

Supported primitive ranges are `boolean`, `date`, `datetime`, `decimal`,
`double`, `float`, `integer`, `string`, `time`, `uri`, and `uriorcurie`.
URI values must be complete RFC 3986 ASCII URIs. URI-or-CURIE values may
also use a valid prefixed CURIE; relative references and invalid percent
escapes are rejected.

Requiredness, scalar or list shape, enum membership, regular-expression
patterns, and numeric bounds remain executable validation rules in the
compiled contract.

## Read the three digests

Every compiled schema exposes three related fingerprints:

``` r

schema@source_digest
schema@structural_digest
schema@build_digest
```

- The source digest binds captured contract input.
- The structural digest changes when mapped acceptance behavior changes.
- The build digest binds the complete compiled manifest and compiler
  metadata.

For data-dict, a change to redacted examples, ranges, origins, or source
locators changes the source and build digests but not the structural
digest. Changing a required field, accepted type, enum, or reference
rule changes the structural digest.

Commit the authored source, resolved exports, generation record, and
compiled manifest together when reproducible contract builds matter.
Runtime systems can then load the checked `.graft.json` without either
source compiler.
