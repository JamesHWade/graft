# Commons contracts relevant to measures phase 3

Date: 2026-08-22

## Source snapshot

This note records the upstream contract at
[`posit-dev/commons@4b2cd5a`](https://github.com/posit-dev/commons/tree/4b2cd5a92e573506dbd9341d61072de6780eb84a)
(package version `0.0.0.9002`). All links below are pinned to that commit.
Commons describes itself as highly experimental and warns that its interface
may change rapidly, so this is a compatibility target, not a promise of future
stability
([`README.md:8-13`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/README.md#L8-L13),
[`DESCRIPTION:1-18`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/DESCRIPTION#L1-L18)).

## R-function measure discovery

The supported entry point is `commons::semantic_layer(...)`, not
`read_measures()`: `semantic_layer()` is exported and accepts `measure()`
objects, lists, R-script paths, and directory paths, while `read_measures()` is
internal
([`R/measures.R:1-18,66-113`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/measures.R#L1-L113),
[`NAMESPACE:3-13`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/NAMESPACE#L3-L13)).

Discovery has these concrete semantics:

- A directory contributes its immediate `.R` and `.r` files; discovery is not
  recursive. Missing paths error. Duplicate resolved file paths are removed
  ([`resolve_measure_files()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/read-measures.R#L63-L80)).
- Loading is executable, not declarative. `read_measures()` first `sys.source()`s
  every resolved file into one shared child environment, in file order, then
  parses its roxygen blocks. Helpers in sibling files work only when those files
  are passed in one path argument/read operation; separate path arguments to
  `semantic_layer()` are isolated
  ([`R/read-measures.R:19-38`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/read-measures.R#L19-L38),
  [tests](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/tests/testthat/test-read-measures.R#L178-L230)).
- Only a roxygen block containing the toggle tag `@measure` is considered. Its
  object topic must resolve to a function in the sourced environment. The
  function name becomes the measure name; title, description, and `@return`
  text are concatenated into the model-visible description
  ([`block_to_measure()` and `block_description()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/read-measures.R#L82-L115)).
- A formal documented with `@param` is model-supplied. A formal without
  `@param` is hidden from the model and treated as an injection: an argument
  named for a Commons data source receives that source's DBI connection;
  otherwise it must have a usable default
  ([`block_arguments()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/read-measures.R#L117-L135),
  [`resolve_injections()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/measures.R#L183-L227),
  [`measure_injectables()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/commons.R#L421-L425)).
- A leading code span in `@param` selects the Ellmer type. Commons recognizes
  scalar `string`, `integer`, `number`, and `boolean`; `enum[a, b]`; and array
  forms such as `string[]`. Without a recognized span, it infers from the
  formal's default and falls back to string. Requiredness comes from the
  absence of a default, not the type declaration
  ([`param_type()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/read-measures.R#L137-L205),
  [type tests](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/tests/testthat/test-read-measures.R#L35-L116)).
- Measure names must be unique after all inputs are expanded. File-based
  measures and helper source text are retained for the agent's `run_r` session,
  but their closure environments and credentials are not
  ([`semantic_layer()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/measures.R#L68-L88),
  [source visibility contract](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/measures.R#L24-L34)).

## `@provenance` convention

Commons' first-party skill specifies one or more `#' @provenance` tags on each
measure. Prefer a host permalink that pins repository, commit, path, and line
range in one URL, for example:

```text
https://github.com/org/repo/blob/<sha>/R/server.R#L120-L145
```

The host-neutral fallback is `<repo-url>@<sha> <path>#L<start>-L<end>`.
Non-versioned sources use `<location> (retrieved <yyyy-mm-dd>)`; measures born
from trajectory work use `trajectory analysis (<yyyy-mm-dd>)`
([`inst/skills/commons/SKILL.md:49-67`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/inst/skills/commons/SKILL.md#L49-L67)).

This is currently a convention rather than an enforced runtime record.
`read_measures()` registers `@provenance` as a free-form value tag so roxygen
can parse it, but `block_to_measure()` does not read, validate, or attach the
value. The tag does not reach the model; tests confirm that arbitrary provenance
strings leave the resulting tool name, description, and argument schema
unchanged
([`R/read-measures.R:1-13,88-103`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/read-measures.R#L1-L103),
[`tests/testthat/test-read-measures.R:290-322`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/tests/testthat/test-read-measures.R#L290-L322)).

## `data_source()` and a read-only DuckDB connection

The public constructor is
`data_source(..., tables = NULL, exclude = NULL, dictionary = NULL)`. A single
`DBIConnection` is wrapped and queried as-is; Commons neither copies it nor
owns/disconnects it. With `tables = NULL`, Commons exposes the result of
`DBI::dbListTables()`. With explicit character names or `DBI::Id` objects, it
normalizes identifiers and verifies them with a zero-row query, falling back to
`DBI::dbExistsTable()` to identify failures
([`R/data-source.R:1-38,120-149`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/data-source.R#L1-L149),
[`data_source_connection()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/data-source.R#L181-L325),
[`check_table_ids_exist()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/data-source.R#L949-L991)).
The result is a concrete `commons_data_source`; Commons does not publish a
subclassing or adapter protocol beyond supplying one of the constructor's
accepted inputs.

There is also a fully Commons-owned path: pass one or more named data frames,
for example `data_source(observations = frame)`. Commons requires at least one
argument, requires every argument to be named and inherit from `data.frame`, and
uses each argument name as the DuckDB table name. It creates an in-process
DuckDB connection, copies the frames with `dbWriteTable()`, applies its extension
and filesystem lockdown, and marks the connection as owned so its finalizer
disconnects it
([`data_source_frames()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/data-source.R#L151-L169),
[`check_named_frames()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/data-source.R#L1095-L1112),
[`new_data_source()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/data-source.R#L396-L446)).
This is a construction-time copy, not a live view of the original frames. The
tests verify that the named table is queryable and that Commons' lockdown
prevents re-enabling external access
([`tests/testthat/test-data-source.R:1-7,116-121`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/tests/testthat/test-data-source.R#L1-L121)).

Both construction paths support file-measure injection. When a source is passed
to `commons()` in a named `data_sources` list, an undocumented measure formal
with that same name receives the source's underlying DBI connection. The source
currently exposes that connection as `$con`, but there is no exported connection
accessor; injection is the documented measure-facing contract
([`measure_injectables()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/commons.R#L421-L425),
[`tests/testthat/test-commons.R:298-328`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/tests/testthat/test-commons.R#L298-L328)).

For a caller-supplied connection, the read-only contract belongs to the caller.
Commons rejects obvious non-`SELECT`/`WITH` and multi-statement SQL before
execution, but explicitly calls this a safeguard rather than a sandbox and
instructs users to open their connection read-only where the backend supports
it
([`R/data-source.R:99-109`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/data-source.R#L99-L109),
[`check_query()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/data-source.R#L748-L806)).
Commons applies its stronger DuckDB hardening only to DuckDB connections it
creates itself; it does not apply those settings to a supplied connection
([`duckdb_lock_down()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/data-source.R#L808-L824)).

The supplied connection must remain open for the Commons data source's lifetime.
Commons queries it with ordinary DBI methods for schema samples and SQL, and its
finalizer disconnects only Commons-owned connections
([`new_data_source()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/data-source.R#L396-L446),
[`source_describe()` and `source_query()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/data-source.R#L605-L745)).
If a dictionary carries definitions, the connection must inherit
`duckdb_connection` for Commons to select its `SQL(duckdb)` compiler
([`definition_source_target()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/definition-compile.R#L238-L260)).

## Generated `data-dict.yaml`

`data_source(dictionary = ...)` publicly accepts a filesystem path, not a raw R
list. Commons reads it with `yaml::read_yaml()` and normalizes this shape:

```yaml
$version: "0.1.0"          # accepted metadata; Commons does not require it
name: Example source       # optional
description: Dataset prose # optional
details: More prose        # optional
tables:
  - name: observations
    description: One row per observation.
    details: Optional table caveat.
    columns:
      - name: count
        type: number
        description: Individuals observed.
    definitions:
      - name: total_individuals
        label: Total individuals observed
        description: Sum of observed individuals.
        expr: SUM(count)
relationships:
  - join: observations.site_id = sites.site_id
    cardinality: many-to-one
glossary:
  site: A monitored location.
```

`tables`, `columns`, and `definitions` may be name-bearing sequences as above
or pre-keyed maps. Commons requires names when normalizing sequences. It retains
top-level `name`, `description`, `details`, `tables`, `relationships`, and
`glossary`; missing sections and unknown fields are tolerated
([`R/data-dictionary.R:1-109`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/data-dictionary.R#L1-L109),
[`tests/testthat/test-data-dictionary.R:1-105`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/tests/testthat/test-data-dictionary.R#L1-L105)).

Dataset prose and glossary content become ambient context; table prose,
documented columns, relationships, and definitions arrive on first touch.
Dictionary prose and definitions also enter context search
([`data_source()` dictionary contract](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/data-source.R#L65-L97),
[`data-dictionaries.md:42-50`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/inst/skills/commons/references/data-dictionaries.md#L42-L50)).

Table-level definitions are stricter than the surrounding prose. Each requires
`name` and non-empty `expr`; `label`, `description`, and `details` are optional
strings. Every referenced column must be declared with a usable type,
definitions must not shadow columns or form cycles, and definitions must belong
to exposed tables. Commons parses and type-checks the data-dict expression,
infers `metric`, `filter`, or `derived` kind, and compiles it when the data source
is constructed
([`data-dictionaries.md:58-76`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/inst/skills/commons/references/data-dictionaries.md#L58-L76),
[`definition_export_table()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/definition-export.R#L31-L100),
[`definition_prepare_envelopes()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/definition-export.R#L102-L133)).

## Lifecycle, errors, and dependencies

- The exported public seams for this interop are `semantic_layer()`, `measure()`,
  `data_source()`, and `list_tables()`. `read_measures()`, `data_dictionary()`,
  and `new_data_source()` are internal and are not exported
  ([`NAMESPACE`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/NAMESPACE#L3-L13)).
- Relevant upstream runtime dependencies are `DBI`, `duckdb (>= 1.5.4.2)`,
  `ellmer (>= 0.4.1)`, `rlang`, and `roxygen2`. `yaml` is only in `Suggests`,
  but dictionary loading checks for it at runtime, so dictionary-backed interop
  cannot work without it
  ([`DESCRIPTION:19-65`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/DESCRIPTION#L19-L65),
  [`data_dictionary()`](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/data-dictionary.R#L1-L21)).
- The inspected paths report failures with `cli::cli_abort()` and do not attach
  Commons-specific condition subclasses. This means message text and generic
  `rlang_error` inheritance are observable today, but neither is a strong
  compatibility boundary. Parent DBI/parser errors are attached in some paths
  ([measure-loading errors](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/read-measures.R#L15-L17),
  [connection-validation errors](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/data-source.R#L953-L991),
  [definition errors](https://github.com/posit-dev/commons/blob/4b2cd5a92e573506dbd9341d61072de6780eb84a/R/definition-export.R#L102-L133)).

## Constraints to carry into the phase 3 design

1. Target the pinned public constructors; do not couple Graft to Commons'
   internal loaders or concrete list layout.
2. Treat measure files as trusted executable R, and preserve Commons' distinction
   between documented model arguments and undocumented connection injections.
3. Treat `@provenance` as retained source convention, not as a value Commons can
   currently validate or return.
4. Preserve the ownership distinction. Named frames produce a hardened,
   Commons-owned DuckDB copy whose table names come from argument names; a
   supplied DBI connection remains caller-owned and must actually be read-only.
   Give the latter an explicit exposed-table registry because implicit discovery
   exposes every table returned by `dbListTables()`.
5. Materialize a real YAML path whose table and column names match the exposed
   relations. Expect construction-time errors for invalid definitions or
   unavailable tables.
6. Pin compatibility tests to an upstream Commons commit/version and retest on
   upgrade because the package explicitly disclaims interface stability.
