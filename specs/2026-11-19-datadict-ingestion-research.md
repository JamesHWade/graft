# data-dict ingestion research (2026-11-19)

## Scope and pins

This is an offline review of the public `tidyverse/data-dict` producer and the
proposed Commons ingestion seam. It does not add a parser, a runtime API, or an
upstream change. The inspected upstream checkout is `main` at
`0161d460b6eb70d337028f8eddbf2f443bcb8f67` (2026-09-11, “Continue to polish
report UI (#256)”). The Graft compatibility baseline is
`0d486ee8a7303a8341bd28aba5e336ec4e2bb9f1`.

The source links in this note are pinned to those commits. “Inspected” means
source, documentation, fixtures, and tests were read. “Executed” means the
command was run in the task-local checkout/environment; generated code was not
treated as proof that the target backend was executed.

## Executive result

The current public seam is a versioned JSON export, not a complete typed
execution IR. `data-dict export-spec` emits resolved definitions with `kind`,
primitive `type`, direct column references, direct definition references, and
per-target translations. The export format is `$version: "0.1.0"`; the R
package is `0.1.0`, while the Rust workspace/CLI is `0.0.3`. The export
implementation documents the format version and top-level fields here
[export.rs](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/crates/data-dict/src/export.rs#L32-L70) and the
definition schema here
[export.rs definition schema](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/crates/data-dict/src/export.rs#L186-L263).
The package and workspace version declarations are respectively
[r/DESCRIPTION](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/r/DESCRIPTION#L1-L4) and
[Cargo.toml](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/Cargo.toml#L10-L18).

The important gap for Commons is grain. Internally the checker distinguishes
constant, aggregate, and row shapes, but the public export collapses constant
and aggregate to `kind: "metric"`, and row plus mixed-grain expressions to
`kind: "derived"`. The exporter’s mapping is explicit
[export.rs kind mapping](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/crates/data-dict/src/export.rs#L776-L826); the internal shape model is
[assert_expr.rs shapes](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/crates/data-dict/src/assert_expr.rs#L1008-L1051). Therefore the current export cannot by itself satisfy a Commons contract that needs to distinguish scalar constant, aggregate metric, row expression, and mixed grain. Those fields must be an explicitly proposed upstream extension or fixture-only metadata; they must not be presented as current producer output.

The second architectural result is that translations are not dependency-expanded.
A reference to a sibling definition is deliberately rendered as its bare name;
the exporter says that recursive substitution is the consumer’s job
[export.rs translation composition](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/crates/data-dict/src/export.rs#L942-L977). Commons can therefore compose a validated dependency graph without introducing a Graft compiler, but must reject cycles/missing references and must not assume a translation string is independently runnable.

## Current public entrypoints and export shape

The R package has no separate resolved-export function. Its public interface is
a thin binary wrapper: `dd_run()` invokes the configured `data-dict` executable,
captures stdout and stderr together, and treats a non-zero status as an error
[R binary wrapper](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/r/R/binary.R#L54-L106). Consequently, an R caller obtains the resolved export with the public command `dd_run(c("export-spec", ...))`, rather than with an R-native export object. `dd_validate_data()` is a different wrapper around `render-report`; it returns an HTML path and status, and intentionally does not throw merely because the dataset failed validation
[R validation wrapper](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/r/R/validate.R#L23-L58).

At the JSON level, the current shape is:

```json
{
  "$version": "0.1.0",
  "name?": "...",
  "version?": {"number|date|hash": "..."},
  "tables": [
    {
      "name": "...",
      "source?": {"parquet": "relative/path.parquet"},
      "rows?": 123,
      "columns": [
        {"name": "...", "type": "number", "range?": {"min": 0, "max": 10}}
      ],
      "constraints?": ["assertion"],
      "definitions?": ["definition"],
      "profile?": "..."
    }
  ],
  "relationships?": [],
  "glossary?": []
}
```

Optional empty values are omitted. The table/source/column fields and the
supported Parquet source are defined in the exporter
[export.rs table and column schema](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/crates/data-dict/src/export.rs#L99-L172), and the same omission and JSON contract is documented in
[site/export.md](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/site/export.md#L25-L95).

Each assertion or definition can contain:

* `expression`, with optional author `language`, `canonical`, `fidelity`, and
  `notes`;
* `kind`: `filter`, `metric`, or `derived`;
* primitive `type`: `number`, `string`, `boolean`, `date`, `datetime`, or
  `interval` (complex/unknown types are omitted);
* direct `columns` and direct `definitions`; and
* `translations`, each with `target` and either `code` or `error`, plus optional
  divergence `notes`.

These fields and their omission rules are part of the implementation
[export.rs assertion/definition/translation schema](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/crates/data-dict/src/export.rs#L186-L263). The public documentation confirms that references are direct, first-appearance-order references, not transitive closure
[site/export.md definitions](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/site/export.md#L136-L166).

## Expression kind, type, dependencies, and grain

The internal type checker carries `ty` and `shape`; `Shape` has `Const`, `Agg`,
and `Row`, with aggregate/row propagation and mixed-grain expressions allowed
[assert_expr.rs type environment and shapes](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/crates/data-dict/src/assert_expr.rs#L883-L915),
[expressions.md shape semantics](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/site/expressions.md#L89-L109). The public exporter then applies this lossy mapping:

| Internal result | Current export `kind` | Consequence |
| --- | --- | --- |
| `Const` | `metric` | A scalar constant is indistinguishable from an aggregate metric. |
| `Agg` | `metric` | The export does not say “aggregate”. |
| `Row` and non-boolean | `derived` | A row expression is not explicitly row-grain. |
| `Row` boolean | `filter` | This is the only public kind that identifies a role directly. |
| Mixed row + aggregate | `derived` | Mixed grain is not marked or rejected by data-dict. |

`columns` and `definitions` are direct references. A definition reference is
not expanded into the referenced definition’s columns or code in the same
record; `collect_columns()` explicitly keeps the two lists separate
[export.rs direct reference collection](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/crates/data-dict/src/export.rs#L979-L1025). The documented consumer operation is recursive substitution using the sibling definition’s translation, with the dependency graph supplied by `definitions`.

### Executed counterexample

Against a task-local dictionary containing `doubled = revenue * 2`,
`total = SUM(revenue)`, `mixed = SUM(doubled) + revenue`, and `constant = 42`,
the pinned CLI emitted (status 0):

* `doubled`: `kind: "derived"`, `type: "number"`, direct `columns: ["revenue"]`;
* `total`: `kind: "metric"`, `type: "number"`, direct `columns: ["revenue"]`;
* `mixed`: `kind: "derived"`, `type: "number"`, direct `columns: ["revenue"]`,
  `definitions: ["doubled"]`;
* `constant`: `kind: "metric"`, `type: "number"`, with no column or definition.

The `mixed` translations were `sum("doubled") + "revenue"`,
`sum(doubled, na.rm = TRUE) + revenue`, and
`pl.col("doubled").sum() + pl.col("revenue")`; they were not expanded to
`sum(revenue * 2) + revenue`. This is executed evidence of the source-level
contract described by the exporter, not an inferred parser behavior.

This matches the historical Graft findings: data-dict accepts
`SUM(revenue) + revenue` as a derived number while Commons grouping rejects
mixed grain, and data-dict accepts an R-language rule such as `!is.na(revenue)`
where the existing Commons constructor rejects raw `!`
[Graft semantic compatibility](https://github.com/JamesHWade/graft/blob/0d486ee8a7303a8341bd28aba5e336ec4e2bb9f1/specs/2026-09-16-semantic-compatibility.md#L19-L34).

## Languages, targets, and numerical caveats

The current executable’s default translation registry is exactly:
`SQL(duckdb)`, `R(tidyverse)`, `R(base)`, `R(data.table)`, and
`Python(polars)`. `SQL(data-dict)` is a named opt-in target; it is excluded
from default export translations because it would repeat the source language
[translate.rs target registry](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/crates/data-dict/src/translate.rs#L25-L47). The accepted source-language tags are `sql`, `r`, and `python`; the source/target asymmetry and finite supported surfaces are documented in
[expression-execution.md languages](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/site/expression-execution.md#L82-L98).

The docs describe `SQL(ANSI)`, `SQL(postgres)`, and `Python(pandas)` as target
families/dialects, but at this pinned executable they are not emitters. An
executed `translate --target` probe returned status 1 and listed only
`SQL(duckdb)`, the three R targets, `Python(polars)`, and
`SQL(data-dict)` as available. The implementation’s family defaults explicitly
say that the ANSI default is “not available yet”
[translate.rs target resolver](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/crates/data-dict/src/translate.rs#L49-L85). Thus Commons should record the exact target name and preserve a per-target `error`; it should not silently interpret a documented-but-unimplemented dialect as supported.

Translation output is a bare expression intended for a caller’s filter/WHERE
context, not a runnable script that loads data or composes definitions
[expression-execution.md bare translations](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/site/expression-execution.md#L62-L80). Fidelity is per translation (`exact`, `guarded`, `divergent`, or `unsupported` in the semantic documentation), while the export currently records `fidelity: "divergent"` for foreign-language readings and puts target-specific caveats in translation `notes`; a target refusal is an `error` rather than a global export failure
[expression-execution.md fidelity](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/site/expression-execution.md#L138-L159).

Important numerical caveats inspected in the pinned execution documentation:

* R rounds half values to even, has no native 64-bit integer type, and differs
  on empty/all-null aggregate identities.
* Polars and pandas use different empty/all-null aggregate identities and can
  wrap integer arithmetic at 64 bits.
* DuckDB and the data-dict language agree on several aggregate semantics, but
  differ from R/Polars on NaN/null and integer-overflow edge cases.
* The language’s integer overflow is a validation/no-result condition; a bare
  translated expression cannot guarantee that behavior across every target.

The standing differences, including rounding, empty/all-null aggregates,
overflow, division by zero, and NaN, are enumerated in
[expression-execution.md standing divergences](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/site/expression-execution.md#L161-L177). These are translation caveats, not evidence that any target backend was executed. The Graft baseline recorded DuckDB verification and left Snowflake, Databricks, R, and Python execution unproved
[Graft backend boundary](https://github.com/JamesHWade/graft/blob/0d486ee8a7303a8341bd28aba5e336ec4e2bb9f1/specs/2026-09-16-semantic-compatibility.md#L50-L79).

## Validation, provenance, and digest gaps

`export-spec` validates the dictionary/spec and serializes the resolved export;
`export-data` profiles source data but explicitly does not validate data
values. The implementation returns a problem set plus optional export and
documents that profiling is not data validation
[export.rs export entrypoints](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/crates/data-dict/src/export.rs#L447-L503),
[site/export.md export semantics](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/site/export.md#L1-L23). A successful export JSON therefore has no producer-written validation status, data-read status, or eligibility receipt.

Validation status is carried by a separate report. The report has its own
`$version: "0.1.0"`, status, steps, problems, failed rows, and run metadata;
the run metadata includes dictionary path, validation level/table, timestamp,
and tool version, but not an input dictionary/data SHA-256 digest
[report.rs report shape](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/crates/data-dict/src/report.rs#L28-L29),
[report.md report provenance](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/site/report.md#L17-L32),
[report.rs run metadata](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/crates/data-dict/src/report.rs#L510-L578). The table source itself is only a relative Parquet path
[export.rs source](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/crates/data-dict/src/export.rs#L99-L128).

The resulting gaps are material for admission:

1. There is no source digest, dictionary-content digest, export-content digest,
   validation-run identity, or generator timestamp in the export contract.
2. The `version` field is user metadata (number/date/hash), not a content
   digest or proof that a particular source was read.
3. `export-data` may produce a partial/profiled document with warnings when a
   source is absent or unreadable; a Commons consumer must not infer that the
   data passed value validation from a successful export.
4. Translation notes/fidelity describe known semantic differences; they do not
   prove target execution or faithful numerical results.

Commons should therefore require an external, host-bound receipt containing
the exact dictionary/export/input bytes (or cryptographic digests), selected
validation report/status, selected target translations, and host observations.
Those receipt fields are proposed ingestion metadata, not current data-dict
output. Source bindings should be host-supplied and digest-checked; paths in an
untrusted export must not be interpreted as authority.

## Compatibility recommendation

The feasible bounded contract is a versioned typed export envelope with the
current producer payload preserved verbatim plus an explicit compatibility
extension. The extension should add, for each definition, fields such as:

```json
{
  "grain": "scalar" | "row" | "aggregate" | "mixed",
  "value_type": "number",
  "expression_kind": "filter" | "metric" | "derived",
  "dependencies": {"columns": [], "definitions": []}
}
```

`grain` and the distinction between scalar constant and aggregate are proposed
fields, not claims about the current producer. The current `kind`, `type`,
`columns`, `definitions`, `language`, `canonical`, `fidelity`, `notes`, and
per-target `translations` should remain intact. The extension should declare
whether dependency translations are direct/bare (current behavior) or fully
expanded; for this pinned producer it must say “direct/bare; consumer composes”.

The Commons side can safely own:

* schema/version gating, required-field and digest/receipt checks;
* dependency graph validation, with executable sibling composition deferred
  until an upstream-defined symbol/template contract is available;
* source binding, supported backend selection, invocation evidence, and
  rejection of unsupported target/errors;
* query-role checks (scalar/aggregate metric, row dimension, boolean filter,
  mixed-grain rejection) without parsing or lowering expression strings.

The current bare translation strings and direct-name lists do not by themselves
make composition or physical-name rewriting safe. Current Commons uses its
private typed representation and collision-free markers for that work; a public
resolved path needs an agreed reference-aware target template or equivalent
structured representation. The proposed fixture retains dependency closure but
does not implement or qualify executable composition.

The producer/data-dict side should own expression parsing/type checking,
translation generation, language/dialect fidelity, and data-dict value
validation. This preserves the Graft boundary: no new Graft compiler, SQL
string substitution engine, arbitrary R evaluation, or runtime API is needed.
The existing compatibility spec assigns validation/resolved export to
data-dict, source binding/dependency composition/backend execution to Commons,
and retained provenance/artifacts to the host
[Graft ownership boundary](https://github.com/JamesHWade/graft/blob/0d486ee8a7303a8341bd28aba5e336ec4e2bb9f1/specs/2026-09-16-semantic-compatibility.md#L81-L93).

Current export-only payloads should be rejected for a contract requiring
explicit grain or an admission receipt. A conformance fixture may hand-author
the proposed `grain`/receipt fields, but must label them as proposed fixture
metadata and keep the raw current export alongside them; it must not fabricate
them as if emitted by `data-dict`.

## Runtime validation evidence and commands

Executed in task-local paths under `/private/tmp/ellmerverse-2026-11-19`:

```text
CARGO_TARGET_DIR=/private/tmp/ellmerverse-2026-11-19/targets/data-dict-cli \
  cargo build --release --locked -p data-dict-cli
```

Result: success. The binary was
`/private/tmp/ellmerverse-2026-11-19/targets/data-dict-cli/release/data-dict`,
reported `data-dict 0.0.3`, and had SHA-256
`80f9966576808ec2ec7b9798b85761acf356bb48f0703b29abd2502c3bf19826`.

```text
CARGO_TARGET_DIR=/private/tmp/ellmerverse-2026-11-19/targets/data-dict-cli \
  cargo test --locked -p data-dict export -- --nocapture
CARGO_TARGET_DIR=/private/tmp/ellmerverse-2026-11-19/targets/data-dict-cli \
  cargo test --locked -p data-dict-cli -- --nocapture
```

The focused export test run passed 16 tests. The full CLI test run passed 29
unit tests and 33 CLI integration tests after running with the local socket
permission required by live-server tests. A task-local R installation of
`datadict` (`R_LIBS_USER=/private/tmp/ellmerverse-2026-11-19/R-lib`) was also
made; no user-library or system changes were made.

The minimal public R probe used:

```r
library(datadict)
dd_run(c("export-spec", "--pretty", "/path/to/data-dict.yaml"))
```

with `DATA_DICT` pointing to the pinned task-local binary. It returned status 0
and captured warnings plus JSON, confirming that the public R route is the CLI
wrapper rather than a native export object. The source package version is
`0.1.0`; the CLI/version distinction is therefore a dependency pin that a
consumer should record.

The following are feasible bounded checks for a pinned fixture:

```text
data-dict export-spec --pretty DICTIONARY
data-dict export-data --pretty DICTIONARY
data-dict validate-data --json DICTIONARY
data-dict translate --target SQL(data-dict) DICTIONARY
data-dict translate --target SQL(duckdb) DICTIONARY
data-dict translate --target R(base) DICTIONARY
data-dict translate --target R(tidyverse) DICTIONARY
data-dict translate --target R(data.table) DICTIONARY
data-dict translate --target Python(polars) DICTIONARY
```

`export-data` is profile-only; `validate-data --json` is the command whose
separate report/status must be retained. The executable needs Rust locked
dependencies, a Parquet source for data profiling/validation, and the pinned
binary; the R wrapper additionally needs R, `cli`, and `processx`. Snowflake,
Databricks, R-backend, and Python-backend execution were inspected in the
documentation/boundary only and were not executed here.

The locked build also resolves the `quarto-yaml` and
`quarto-yaml-validation` git dependencies to
`ef1580a396baf0508537b02a662b6aa7c2323bfb`, as recorded in
[Cargo.lock](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/Cargo.lock#L1578-L1598).
