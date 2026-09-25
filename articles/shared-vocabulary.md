# Shared concepts across workflows

Graft publishes a shared vocabulary alongside persistent artifacts.
Data-dict owns each workflow’s table contract. Commons can use the
published context with its local dictionaries, and plain R can read the
same release.

## Publish one release

The bundled example describes two laboratories that use different names,
units, and measurement conditions. Concepts say what fields describe.
Relationships give a direction and name their domain and range concepts.
Qualified bindings keep each workflow’s table, field, identity scope,
grain, and condition.

``` r

library(graft)
path <- system.file("examples", "vocabulary", "v1", "bindings.json", package = "graft")
store <- graft_store("lab-vocabulary", create = TRUE)
release <- graft_publish_vocabulary(store, path)
reopened <- graft_read_vocabulary(store, release)
release@selection@id
cat(paste(reopened@context, collapse = "\n"))
```

Publishing requires `datadict` and its data-dict binary. Graft runs the
public `validate-spec` and `export-spec` commands against captured
dictionary bytes. It keeps the exact companion JSON, vocabulary JSON,
dictionary YAML, resolved exports, validation provenance (including the
binary digest), and generated Markdown in one artifact selection. Each
source file must be self-contained and is limited to 1 MiB. A release
can contain at most 498 dictionaries, and its sources and generated
outputs must fit the artifact store’s aggregate byte limit. Graft checks
the dictionary count and source sizes before running data-dict, then
checks the fully encoded release before writing artifacts. It does not
parse dictionary YAML or evaluate expressions.

Reads verify every artifact in the retained release and rebuild the
context from it. They need neither the original files nor an installed
data-dict binary. This checks content integrity. It is not a signature
or independent proof of the publisher’s identity or claims. Stores
retain the trusted local storage limits described in [persistent
artifacts](https://jameshwade.github.io/graft/articles/persistent-artifacts.md).

[`graft_publish_vocabulary()`](https://jameshwade.github.io/graft/reference/graft_publish_vocabulary.md)
returns a `VocabularyRelease`. Its `@selection` property is an
`ArtifactSelection`, so applications can retain the exact release
selection without handling a bare digest. When reopening the release,
[`graft_read_vocabulary()`](https://jameshwade.github.io/graft/reference/graft_read_vocabulary.md)
accepts the release, an `ArtifactSelection`, or the exact selection
digest.

## Companion format

A `graft-bindings/1` JSON file has six fields:

| Field | Meaning |
|----|----|
| `format` | `graft-bindings/1` |
| `release` | Caller-owned release identifier |
| `vocabulary` | Vocabulary `release`, sibling `path`, and SHA-256 `sha256` |
| `dictionaries` | Array of dictionary release `id`, `workflow`, sibling `path`, and `sha256` references |
| `bindings` | Array of concept or relationship bindings |
| `assertions` | Array of explicitly qualified assertions, which may be empty |

Vocabulary files use `graft-vocabulary/1`, a `release`, and an array of
`terms`. Each term has a stable `id`, `kind` (`concept` or
`relationship`), `definition`, and an array of `aliases`. A relationship
also names `domain` and `range` concept IDs. Aliases are descriptive
labels. They do not create equivalence or resolution rules.

Each binding has `id`, `kind`, `dictionary`, `table`, `term`, `scope`,
`grain`, and `condition`. A concept binding names one `field`; a
relationship binding names `from` and `to` fields. Each endpoint must
have a concept binding that matches the relationship’s domain or range
and its scope, grain, and condition. Graft rejects multiple concepts for
one dictionary/table/field, even when they have different
qualifications.

Each assertion has `id`, `subject`, `predicate`, `object`, `source`,
`status`, `negated`, `time`, and `scope`. The predicate must name a
declared relationship. Status is `draft`, `accepted`, or `retracted`;
negation is Boolean. Subjects and objects are opaque application
identities, and Graft does not check whether they belong to the domain
and range. These values are publisher statements, not Graft decisions.
Time and condition are descriptive strings, not executable rules.

See the [complete example
files](https://github.com/JamesHWade/graft/tree/main/inst/examples/vocabulary)
for every field. Publication fails when bindings are missing, unknown,
duplicate, or ambiguous.

## Use the same release in R and Commons

Plain R can inspect a binding and select its local field without
guessing a join. `@bindings` is the retained companion record, and its
`bindings` member contains the raw binding fields from the file:

``` r

bindings <- Filter(function(x) x$kind == "concept" &&
  x$term == "urn:example:temperature", release@bindings$bindings)
lapply(bindings, function(x) x[c("dictionary", "table", "field", "scope", "grain", "condition")])
```

A Commons caller supplies the generated context alongside its own
dictionary:

``` r

context_file <- tempfile(fileext = ".md")
writeLines(release@context, context_file)
context <- commons::context_layer(files = context_file)
source <- commons::data_source(
  readings = data.frame(reading_id = "r1", sample_id = "s1", temperature_c = 20),
  dictionary = file.path(dirname(path), "lab-a.yaml")
)
# Supply context and source to the Commons host; retain release@references
# and release@selection with resulting artifacts.
```

The integration test constructs a real Commons object with the published
context. It checks that Commons accepts and uses the context when
constructing the object, not model retrieval quality or factual
reasoning. Shared concepts do not establish safe joins, comparable
units, access permission, or execution authority. Negated and retracted
assertions keep those statuses and remain data; they do not become Graft
decisions. There is no ontology reasoner, unit converter, new expression
compiler, or automatic procedure selection.

## Retain earlier releases

Publish changed dictionaries and bindings as a new release, and keep
both selection digests. A reader of an older release resolves its exact
bytes rather than a mutable latest pointer. Publication does not accept
the release. A host can use Graft’s decision journal when review and a
current use check are needed.

``` r

next_path <- system.file("examples", "vocabulary", "v2", "bindings.json", package = "graft")
next_release <- graft_publish_vocabulary(store, next_path)
original <- graft_read_vocabulary(store, release)
updated <- graft_read_vocabulary(store, next_release)
```
