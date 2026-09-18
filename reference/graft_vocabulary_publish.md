# Publish and read a shared vocabulary release

Validate explicit concepts, directed relationships and qualified
dictionary bindings, then retain their exact source bytes and resolved
dictionary exports in one artifact selection. Publication grants no
approval or execution authority. Reading a historical release does not
re-run data-dict.

## Usage

``` r
graft_vocabulary_publish(store, path)

graft_vocabulary_read(store, selection)
```

## Arguments

- store:

  A
  [`graft_artifact_store()`](https://jameshwade.github.io/graft/reference/graft_artifact_store.md)
  handle.

- path:

  Path to a `graft-bindings/1` JSON companion file. Referenced
  vocabulary JSON and dictionary YAML files must be siblings pinned by
  SHA-256. Each input file is limited to 1 MiB, with at most 498
  dictionaries per release. Sources and generated outputs must fit the
  store's aggregate byte limit. Dictionaries must be self-contained;
  validation/export runs against captured source bytes in a temporary
  file.

- selection:

  Exact selection digest returned by `graft_vocabulary_publish()`.

## Value

`graft_vocabulary_publish()` returns an immutable selection digest.
`graft_vocabulary_read()` returns `vocabulary`, `bindings`,
`dictionaries`, `references`, and `context` (Markdown generated from the
same release).

## Details

The companion format records its release, vocabulary release, dictionary
identities, workflows, source digests, bindings and qualified
assertions. Concepts map to one qualified dictionary/table/field.
Relationships require explicit domain and range concepts and matching
endpoint bindings, including scope, grain and condition. Assertions
retain their source, status, negation, time and scope; publication does
not verify that an assertion is true.

Matching concepts do not prove joins, comparable units, permissions or
program authority. No expression evaluation, ontology inference or code
loading occurs. See the shared vocabulary article for the complete
companion format.

Publishing requires the optional `datadict` package and an installed
data-dict binary. Only its public `validate-spec` and `export-spec`
commands are used. Graft preserves their resolved JSON and validation
provenance; data-dict owns the local table contract. Historical reads
require only Graft.
