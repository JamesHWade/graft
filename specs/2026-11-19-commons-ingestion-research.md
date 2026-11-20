# Commons resolved-dictionary ingestion research

Issue: Graft #65.

This is an offline contract proposal, not a production API or an upstream
contribution.

## Result

The historical missing seam is still missing at the current Commons default
branch. Commons now has a useful public, model-free execution surface in R:
`commons(data_sources = ...)` returns an object whose `$metrics()` and
`$run_sql()` methods execute directly. That surface still starts with an
authored `data-dict.yaml` path (or Commons' own normalized dictionary) and
re-parses, type-checks, resolves, and lowers definitions. It does not accept a
canonical/resolved export.

The Python package has the same authored-YAML-only ingestion boundary. Its
root exports include `DataSource` and `Commons`, but no resolved-export type or
constructor. Its `Commons` agent requires a `chatlas.Chat`; its direct governed
query function is an internal pool function, not a public package method.

Therefore #65 should keep the proposed boundary: Graft must not become a
second data-dict parser, dependency resolver, or SQL lowerer. The missing
upstream work is a versioned resolved-export object accepted by a public
Commons data-source constructor.

## Sources and evidence labels

The source checkout is `/private/tmp/ellmerverse-2026-11-19/sources/commons`,
`posit-dev/commons` `main` at
`03349a71ef3b64c80c6cd53f215ea870db2851a8` (the default branch head on
2026-11-19). The Graft source checkout is at
`0d486ee8a7303a8341bd28aba5e336ec4e2bb9f1`. All source links below are pinned
to the Commons SHA.

“Source inspection” means the code at that commit; it is not a statement that
an unobserved public API exists. “Actual runtime” identifies the separate
detached-sales harness run against this Commons source and ellmer 0.5.1; no
HTTP model response was mocked for those direct R calls.

## Public constructors and ingestion

| Surface | Public shape at the pin | Dictionary input accepted | Resolved export accepted? |
| --- | --- | --- | --- |
| R | `data_source(..., dictionary = NULL)`; `commons(data_sources = ..., semantic_layer = ..., context_layer = ...)` | `NULL`, an existing internal `commons_data_dictionary`, or one path to authored YAML | No |
| Python | `data_source(...)`; `DataSource.from_frames()`, `.from_engine()`, `.from_board()`; `Commons(client, data_sources, ...)` | `None`, a `DataDictionary` instance, or a path to authored YAML | No |

R's package exports list `commons()` and `data_source()` but no dictionary or
export constructor ([`pkg-r/NAMESPACE` lines 4–13](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/NAMESPACE#L4-L13)).
`data_source()` documents `dictionary` as a data-dict YAML path and dispatches
through `as_data_dictionary()` ([`pkg-r/R/data-source.R` lines 62–65](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/data-source.R#L62-L65); [`lines 107–135`](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/data-source.R#L107-L135)). The
R coercion accepts only `NULL`, an existing normalized object, or a single
character path; all other objects are rejected ([`pkg-r/R/data-dictionary.R` lines 20–30](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/data-dictionary.R#L20-L30)). The normalized object is
created internally from YAML and immediately gets Commons' private definition
export attached ([`pkg-r/R/data-dictionary.R` lines 33–50](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/data-dictionary.R#L33-L50)).

R's `commons()` constructor is public and model-free ([`pkg-r/R/commons.R` lines 31–46](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/commons.R#L31-L46); [`lines 157–183`](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/commons.R#L157-L183)); it builds the
normalized data sources and registry ([`pkg-r/R/commons.R` lines 238–253](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/commons.R#L238-L253)). This is the current
public direct route, but it is not a resolved-export route.

Python's root package exports `DataSource`, `data_source`, `Commons`, and
semantic-layer types, but not `DataDictionary`, `DefinitionExport`, or an
export-record constructor ([`pkg-py/src/commons/__init__.py` lines 11–30](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/__init__.py#L11-L30)). The dictionary module explicitly says its
input is authored YAML, never data-dict JSON export ([`pkg-py/src/commons/_data_dictionary.py` lines 1–18](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_data_dictionary.py#L1-L18)); `from_path()` reads YAML and
`as_data_dictionary()` accepts only a path or an existing `DataDictionary`
([`pkg-py/src/commons/_data_dictionary.py` lines 176–186](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_data_dictionary.py#L176-L186); [`lines 394–401`](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_data_dictionary.py#L394-L401)). The dispatcher attaches the
dictionary to frames or passes it to the engine/board constructor, then lowers
it during source construction ([`pkg-py/src/commons/_data_source.py` lines 443–515](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_data_source.py#L443-L515)).
The public frame and engine constructors are implemented at
[`pkg-py/src/commons/_data_source.py` lines 137–190](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_data_source.py#L137-L190) and the board constructor at
[`lines 227–295`](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_data_source.py#L227-L295); none has a resolved-export overload.

## Direct execution without a model

### Public R route

The exact public call shapes are:

```r
source <- data_source(sales = detached_sales, dictionary = "data-dict.yaml")
commons <- commons(data_sources = source)
commons$metrics(
  metrics = "total",
  dimensions = NULL,
  filters = NULL,
  where = NULL,
  arguments = list(),
  source = NULL
)
commons$run_sql("SELECT {{doubled}} FROM sales")
```

`$metrics()` is a public method that forwards to the governed query compiler
and returns its `$result`; `$run_sql()` expands governed tokens, applies the
read-only SQL check, and queries the source ([`pkg-r/R/commons.R` lines 285–334](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/commons.R#L285-L334)). Filter and derived definitions are therefore executable by
passing their names as `filters`/`dimensions` or by using `{{name}}` in SQL.

### Actual runtime evidence

The detached-sales harness used the public R object above against the pinned
Commons source, without a provider client or HTTP mock. It observed:

| Public call | Observed result |
| --- | --- |
| `$metrics("total")` | `total = 35` |
| `$metrics("total_doubled")` | `total_doubled = 70` |
| `$metrics("constant")` | `constant = 42` |
| `$metrics("total", filters = <the governed filter>)` | `total = 15` |
| `$run_sql("SELECT {{doubled}} FROM sales")` | `20, 40, NA, 10` |

This proves direct execution of aggregate, dependency-derived, constant,
filtered, and row-derived definitions on the fixture. It does not prove
resolved-export ingestion: the runtime still received authored YAML.

The direct R results are plain data frames. `$metrics()` returns only
`query_metrics(...)$result` ([`pkg-r/R/commons.R` lines 293–304](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/commons.R#L293-L304)); it does not return a
`Tag.A`/`Tag.B` result, applied-definition record, dictionary digest, or input
identity. The host must capture those separately before storing an output.

### Python route

Python's public `Commons` constructor requires a `chatlas.Chat`, and its
documented interaction surface is `chat()`/`stream_async()` ([`pkg-py/src/commons/_agent.py` lines 67–123](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_agent.py#L67-L123)). The no-model route exists only as
internal implementation:

```python
call_metrics(
    registry, source, label, handles,
    metrics=["total"], dimensions=None, filters=None,
    where=None, arguments=None,
)
```

This function is in `commons._pool`, despite being listed in that module's
`__all__`; it is not root-package API. Its model-facing wrapper is the private
`_call_metrics()` tool with `metrics`, `dimensions`, `filters`, `where`,
`arguments` JSON, and `source` ([`pkg-py/src/commons/_pool.py` lines 266–276](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_pool.py#L266-L276); [`pkg-py/src/commons/_tools.py` lines 564–591](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_tools.py#L564-L591)). Treat this as a diagnostic test seam, not a Graft integration contract.

Python's internal route does return a `ContentToolResult` tagged `Tag.A`, but
that is a private tool result, not the public `DataSource`/`Commons` contract
([`pkg-py/src/commons/_pool.py` lines 356–373](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_pool.py#L356-L373)). The difference from R's direct data-frame route is
important: neither result should be treated as a durable artifact provenance
record without host-side evidence.

## Current export, parsing, and lowering contract

Both implementations carry a temporary, definition-only port of
`data-dict export-spec`, pinned internally to
`d950c5ac90d0ab939d330600f3a5ee1bfde0f604`. The R adapter says it parses and
type-checks authored expressions, resolves direct columns and sibling
definitions, and emits target-specific SQL; it explicitly does not export the
rest of a dictionary ([`pkg-r/R/definition-export.R` lines 1–29](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/definition-export.R#L1-L29)). Python states the same conformance boundary ([`pkg-py/src/commons/_definitions/_export.py` lines 1–16](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_definitions/_export.py#L1-L16)).

The definition records contain expression, kind, value type, direct column
references, sibling-definition references, and translations. R records those
fields directly and keeps typed IR/shape only as private attributes
([`pkg-r/R/definition-export.R` lines 227–249](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/definition-export.R#L227-L249)); Python's `DefinitionExport` has the same fields plus private IR,
shape, and selection fields ([`pkg-py/src/commons/_definitions/_export.py` lines 80–105](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_definitions/_export.py#L80-L105)). There is no export format version, canonical
dictionary digest, source identity, validation receipt, or public resolved
dictionary constructor in either record.

Source construction is where dialect lowering and bindings happen. R supports
`SQL(duckdb)`, `SQL(snowflake)`, and `SQL(databricks)` and rejects other
definition backends ([`pkg-r/R/definition-compile.R` lines 276–312](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/definition-compile.R#L276-L312); [`lines 537–541`](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/definition-compile.R#L537-L541)). Python has the same three target names ([`pkg-py/src/commons/_definitions/_compile.py` lines 30–34](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_definitions/_compile.py#L30-L34)). Python compiles only after a source dialect is known and refuses unsupported dialects, unexposed tables, missing bound columns, and mixed-grain metric dependency chains ([`pkg-py/src/commons/_definitions/_compile.py` lines 123–190](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_definitions/_compile.py#L123-L190); [`lines 240–247`](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_definitions/_compile.py#L240-L247)).

Sibling references are composed in dependency order. R replaces dependency
markers and carries dependency notes ([`pkg-r/R/definition-compile.R` lines 415–467](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/definition-compile.R#L415-L467)); Python's registry intentionally consumes compiled export records and never reaches into the parser or typed IR ([`pkg-py/src/commons/_definitions/_registry.py` lines 1–7](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_definitions/_registry.py#L1-L7)). The registry's `ExportRecord` has SQL, target, notes, authored columns/definition refs, and a derived `mixed_grain` flag, but no version, digest, or immutable source identity ([`pkg-py/src/commons/_definitions/_registry.py` lines 34–60](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_definitions/_registry.py#L34-L60)).

## Binding, identity, grain, and validation

Commons owns authored-to-physical binding. R's catalog merge returns table and
column matches ([`pkg-r/R/catalog.R` lines 329–390](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/catalog.R#L329-L390)), accepts exact, case-normalized, relative, and qualified-suffix table matches ([`pkg-r/R/catalog.R` lines 424–515](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/catalog.R#L424-L515)), and preserves the authored alias while discovered warehouse type/nullability remain authoritative ([`pkg-r/R/catalog.R` lines 548–635](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/catalog.R#L548-L635)). Python has the same `definition_bindings` and keeps authored column spellings in `ExportRecord` while rewriting executable SQL ([`pkg-py/src/commons/_catalog/_core.py` lines 103–130 and 382–433](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_catalog/_core.py#L103-L130)).

The source identity Commons snapshots is the warehouse session (principal,
catalog/schema, and Snowflake roles), not the dictionary or input data. The
R implementation documents the Snowflake/Databricks session check
([`pkg-r/R/catalog-security.R` lines 1–13](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/catalog-security.R#L1-L13); [`lines 94–130`](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/catalog-security.R#L94-L130)); Python records the same session fields and refuses a changed session ([`pkg-py/src/commons/_catalog/_security.py` lines 97–121](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_catalog/_security.py#L97-L121); [`lines 169–182`](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_catalog/_security.py#L169-L182)). The registry's `source` is later filled with the application source label ([`pkg-py/src/commons/_definitions/_registry.py` lines 75–102](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_definitions/_registry.py#L75-L102)); it is not a durable source digest.

Grain behavior is execution-critical. A row expression containing an aggregate,
or inheriting one through sibling definitions, is marked mixed grain; a
metric query is refused because a subquery rewrite would be needed. Python's
fixed-point detection is explicit ([`pkg-py/src/commons/_definitions/_compile.py` lines 53–75](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_definitions/_compile.py#L53-L75)). R uses the typed IR for the same guard ([`pkg-r/R/definition-compile.R` lines 95–128](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/definition-compile.R#L95-L128)). A resolved-export seam must carry equivalent shape/grain information; `kind` alone is insufficient.

Validation at this pin is structural/type validation of definitions plus source
queryability checks. The temporary exporters explicitly say they do not validate
or export the rest of a dictionary ([`pkg-r/R/definition-export.R` lines 11–20](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/definition-export.R#L11-L20)). No data-value validation report, dictionary digest, or input-validation provenance is accepted or retained by the public constructors. A host therefore needs a separate validation receipt and must not infer data validity from a successful Commons construction or a direct result.

## Language, backend, and file-measure ownership

The authored definition language is parsed and lowered to SQL; it is not R or
Python code execution. DuckDB is the local frame/pin backend. Definition SQL
targets are DuckDB, Snowflake, and Databricks in both implementations. Other
engines can be queried when no governed definitions need a target-specific
emitter, but they do not gain a definition compiler by being passed to
`data_source()`.

Snowflake semantic views and Databricks metric views are a separate native
semantic-model import path, not a data-dict resolved-export path ([`pkg-r/R/data-source.R` lines 46–54](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/data-source.R#L46-L54)).

File-backed measures remain a separate semantic-layer concern. R sources files
into a shared environment, retains measure/helper source text, and extracts
`@provenance` tags ([`pkg-r/R/read-measures.R` lines 1–43 and 63–83](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-r/R/read-measures.R#L1-L43)); Python's `semantic_layer()` accepts measures, modules, files, and directories and keeps source text while the worker receives no callable ([`pkg-py/src/commons/_measures.py` lines 418–475 and 507–620](https://github.com/posit-dev/commons/blob/03349a71ef3b64c80c6cd53f215ea870db2851a8/pkg-py/src/commons/_measures.py#L418-L475)). A resolved dictionary export must not absorb these file measures; Graft should not own their source, injection, or execution.

## Proposed seam and architecture implications

The smallest useful upstream seam is a public, versioned resolved-export
object, for example:

```text
ResolvedDictionaryExport {
  format: "data-dict.resolved/v1"
  identity: {canonical_source, dictionary_digest, validation_receipt}
  tables: [
    {name, grain, columns: [...], definitions: [
      {name, kind, type, shape, expression, columns, definitions,
       translations: [{target, code, error, notes}]}
    ]}
  ]
}
```

This is a proposal, not a current Commons type. It must preserve authored
source language, dependency references, scalar/row/aggregate and mixed-grain
metadata, target translations and notes, canonical source identity, and a
dictionary/value-validation receipt. The public Commons constructor should
accept it alongside the authored YAML path, then continue to own:

- binding authored tables/columns to the selected source and checking session
  identity;
- source-specific target selection and physical-name rewriting;
- sibling-translation composition or an explicitly equivalent imported
  composition contract;
- backend execution and invocation-level applied-definition provenance.

Graft should only validate the export version/digest, bind the selected input
identity and validation receipt to its own policy/evidence closure, and call
the public Commons constructor. It should not copy the parser, typed IR,
dependency lowering, backend emitters, or file-measure loader. A plain R
`data.frame` from `$metrics()` is an execution result, not a replacement for
that closure.

## Runtime validation plan for the future seam

Until a public resolved-export constructor exists, the bounded diagnostic
fixture can validate the current authored path with the public R calls above:

1. Construct a DuckDB-backed source from detached rows and authored YAML.
2. Assert total, filtered, derived-dependency, constant, and row-derived
   results; include empty-filter behavior so the global constant grouping rule
   is exercised.
3. Assert negative cases for a missing authored column, unexposed definition
   table, unsupported definition dialect, and mixed-grain dependency.
4. Capture the dictionary bytes/digest, exact detached input digest, selected
   table binding, emitted SQL/target, applied definition names, and validation
   receipt outside Commons, because the direct data-frame API does not return
   them.
5. Once the seam exists, run the same assertions with the resolved export as
   `dictionary` and prove that authored-YAML and resolved-export paths produce
   the same rows and binding/provenance manifest. Exercise Python's internal
   `call_metrics` only as a cross-language diagnostic until Python exposes a
   public direct route.

## Disposition

Current public R direct execution makes model-free runtime validation practical,
but it does not implement canonical/resolved ingestion. Executable resolved
ingestion requires an upstream versioned export/import contract. Issue #65 can
deliver that proposal and its nonexecuting conformance fixture now. Any future
host integration must wait for the implemented public contract; keep file
measures, persistent input identity, validation provenance, approval, and
retention in their existing owners.
