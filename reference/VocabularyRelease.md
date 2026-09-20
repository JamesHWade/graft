# A retained shared vocabulary release

A `VocabularyRelease` describes one verified vocabulary publication. Its
selection identifies the immutable release in the artifact store.
[`graft_read_vocabulary()`](https://jameshwade.github.io/graft/reference/graft_read_vocabulary.md)
reads the other properties from that selection. These properties are
ordinary R values; they do not grant access, approval, or execution
authority.

## Usage

``` r
VocabularyRelease(
  selection = ArtifactSelection(),
  vocabulary = list(),
  bindings = list(),
  dictionaries = list(),
  references = list(),
  context = character(0)
)
```

## Arguments

- selection:

  Exact retained
  [ArtifactSelection](https://jameshwade.github.io/graft/reference/ArtifactSelection.md)
  for this release.

- vocabulary:

  Retained concepts and relationships.

- bindings:

  Validated bindings to pinned dictionary fields.

- dictionaries:

  Canonical retained dictionary exports keyed by ID.

- references:

  Exact source and export references for the release.

- context:

  Literal context stored with the release.
