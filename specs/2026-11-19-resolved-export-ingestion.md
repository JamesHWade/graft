# A public resolved-export boundary for Commons

Issue: [Graft #65](https://github.com/JamesHWade/graft/issues/65).

Status: proposed upstream interface with a source-only conformance fixture.
Nothing here adds a Graft package export or changes Commons or data-dict.

## Outcome

Let data-dict own parsing, type checking, expression meaning, and supported
translations. Let Commons consume that result through a public constructor,
while retaining source binding, dependency composition, query execution, and
separately authored file measures. Graft may preserve the resulting bytes and
evidence; it does not acquire another compiler.

The proposal deliberately distinguishes three things:

1. Current upstream behavior exercised through public interfaces.
2. Additional metadata required by the proposed interface.
3. A fixture that checks the proposed admission and request rules without
   implementing query compilation or claiming existing upstream support.

## Current boundary

The current source pins and archive digests are in
[`tools/resolved-export/pins.json`](../tools/resolved-export/pins.json).
The source audits describe
[Commons](2026-11-19-commons-ingestion-research.md) and
[data-dict](2026-11-19-datadict-ingestion-research.md) separately from runtime
evidence.

Commons now exposes direct `$metrics()` and `$run_sql()` methods. The historical
sales example can run without a model client, provider credentials, or a mocked
model response. The direct metric result is a data frame; its numerical values
do not by themselves carry the older agent route's calculation labels or
translation caveats.

Its authored-dictionary route still parses and compiles definitions independently
of data-dict. The presence of public direct calculation methods does not supply a
public resolved-export constructor.

data-dict's export format `0.1.0` supplies typed columns, definition kinds and
types, direct references, original language and canonical reading, and target
translations with notes or explicit refusal. `export-spec` validates the
dictionary but never reads source data. `export-data` profiles source data and
does not establish data-value validity.

Two execution gaps remain material:

- A definition reference in translated code remains a bare name. Commons still
  needs to compose sibling translations; the export is not a complete query.
- `kind = "metric"` includes both a scalar constant and an aggregate. It does
  not replace explicit scalar, row, aggregate, and mixed-grain metadata.

Bare target code plus a dependency-name list also does not define safe symbol
replacement. The same spelling can occur in a literal, a physical column name,
or a definition reference. Current Commons uses its private typed representation
and collision-free markers to bind and compose expressions. That machinery is
not a public resolved-export interface and is not reused by this fixture.

## Proposed public interface

The following names illustrate an upstream design; they are not available APIs:

```r
# Proposed data-dict wrapper and typed result.
resolved <- datadict::dd_export_spec(dictionary)

# Proposed Commons constructor input, alongside its authored-path input.
source <- commons::data_source(
  sales = detached_sales,
  dictionary = resolved
)
```

The result must have an explicitly versioned typed contract. It must not be
accepted merely because an arbitrary list happens to contain a `tables` field.
An unsupported version produces a diagnostic identifying the expected contract;
there is no silent fallback to reparsing the original expression text.

The host supplies the actual source bindings and validation evidence separately.
An export's relative Parquet path is descriptive metadata, not permission to open
a file or connect to a database. A dictionary's own `version` is also distinct
from the export format version and from the exact dictionary-byte identity.

## Required information and owners

| Information | Owner and required behavior |
| --- | --- |
| Export format and compiler identity | data-dict identifies the supported export contract and producer revision; a display version alone is insufficient to reproduce development behavior. |
| Exact dictionary and export bytes | The producer/host binds content digests to the actual inputs and output, rather than treating a mutable path or authored version label as identity. |
| Typed tables and definitions | data-dict supplies names, types, original expression, canonical reading, kind, and direct column/definition references. Commons validates the received shape and bindings. |
| Explicit grain | data-dict supplies scalar, row, aggregate, or mixed semantics, including dependency-derived grain. Missing information remains unknown; consumers must not infer it from the kind label. |
| Target translation and symbols | data-dict supplies code or an explicit unsupported result for each target, retaining language-reading fidelity and translation notes. Executable composition additionally requires a versioned symbol representation; the current bare code and name lists do not provide it. Commons owns composition and physical binding against that contract. |
| Source binding | The host maps logical tables to exact detached inputs or a separately defined database snapshot. Commons checks that the binding matches the received contract. |
| Data validation | The validator distinguishes dictionary validation, metadata/data-value validation, and profiling, and binds the report to the exact inputs it inspected. The host decides which validation is required for its use. |
| Invocation evidence | Commons records the actual selected definitions, source binding, target, and execution context. A host's input manifest alone does not prove which inputs a calculation used. |
| File measures | Human-authored R measures retain their separate Commons semantic-layer ownership and explicit execution route. They are not converted into dictionary definitions or replaced by import. |

Current exports do not provide all of this information. In particular, the
fixture's proposed grain supplement is authored test data, not a field emitted
by the current CLI. Its validation record is a host observation around trusted
immutable local inputs, not a validator-produced digest-at-read receipt.

The future validation contract should bind identity while reading the validated
input, or validate an explicitly immutable snapshot. Hashing a path before and
after a separate process does not prove that concurrently mutable bytes remained
unchanged throughout validation. The fixture does not qualify that production
boundary.

For the future executable path, the proposed missing representation is a
reference-aware target template: literal target fragments, column-reference
nodes, and definition-reference nodes are distinct. Each reference names its
logical table and symbol. data-dict owns producing that representation; Commons
owns quoting actual bound identifiers and composing definition references under
an explicit parenthesization contract. Neither party searches and replaces
names in an undifferentiated code string. The template format, binding rules,
and its equivalence to the exported expression need upstream agreement and
conformance tests before execution can be enabled.

No such template is emitted by the pinned producer. This fixture does not
implement a template renderer or claim to validate one. Dependency closure is
inspectable metadata only; it is not evidence that target-aware composition or
physical-name rewriting has been solved. An executable consumer must refuse
that missing capability rather than silently fall back to an independent parser.

## Admission and request behavior

Admission checks the supported export shape, exact dictionary/export/input/report
identity, required validation outcome, table bindings, and proposed semantic
metadata. It validates reference names and dependency consistency without parsing
expressions. No path from the export is resolved implicitly.

A request then checks its selected definitions against their declared roles.
Scalar and aggregate metrics remain distinct; row dimensions and boolean filters
need appropriate grain. Mixed-grain expressions cannot silently become valid
grouping dimensions. The selected dependency closure retains each upstream
translation and its caveats without string substitution or target lowering.

The fixture returns a proposed contract/selection record. It never executes that
record as SQL or R, registers a tool, grants authority, or mutates an existing
Commons object. The current Commons route executes the baseline separately.
Consequently, passing both routes still does not demonstrate one shared compiler.

| Condition | Required result |
| --- | --- |
| Dictionary, export, input, or validation-report bytes change | Reject the stale binding; require a fresh export/validation as applicable. |
| Only profiling succeeded, or required data validation failed | Refuse to represent the input as data-validated. |
| Format, backend, or selected translation is unsupported | Return an explicit refusal, preserving the producer's reason where available. |
| Type, grain, reference, or dependency information is missing or inconsistent | Refuse the proposed contract rather than inventing semantics. |
| A language reading or translation carries caveats | Preserve them through selection; do not silently relabel the authored expression as exact target code. |
| A selected expression has mixed grain | Refuse an incompatible metric/dimension/filter role. |
| Import or request fails | Leave the separately constructed Commons source and file-measure layer usable. |

These checks establish consistency within the fixture. Digests and shape checks
are not authentication, authorization, scientific validity, or proof that a
producer faithfully executed the stated computation.

## Owner-specific changes

**data-dict:** add a public typed R export wrapper and a versioned grain contract;
make producer/source/validation identity explicit; preserve language, fidelity,
target refusals, and translation caveats; define the reference-aware target
template needed for composition and physical binding. Define how validation
receipts bind the data actually inspected. Existing raw CLI output remains a
distinct format.

**Commons:** add the public resolved-input constructor path; validate version,
source bindings, types, dependencies, grain, and supported targets; retain
sibling composition and invocation evidence. Keep file measures separate. Where
a backend needs lowering not emitted by data-dict, refuse it in the resolved
path or retain an explicitly named independent compiler path. Do not advertise
compiler unification for that path.

**Graft and hosts:** preserve exact exports, inputs, and evidence through existing
artifact interfaces if an application needs retention. Hosts own access and
acceptance policy. No new Graft parser, semantic evaluator, storage schema, or
production admission API is justified by this proposal.

Publishing upstream changes is a separate step. This issue delivers a reviewable
contract and evidence, not upstream acceptance or a commitment to the illustrative
function names.

## Conformance and limits

The [fixture README](../tools/resolved-export/README.md) gives the exact preparation
and offline commands, source pins, historical input identities, and tested
boundaries. Source download and CLI compilation happen during preparation; the
test runner does not install packages or make network requests.

The historical comparison covers null handling, the total of 35, filtered total
of 15, derived total of 70, one-row constant 42, and exact doubled rows. It also
retains the R-language divergence, mixed-grain refusal, invalid references, and
the distinction between failed data validation and successful profiling.

The proposed-interface cases exercise stale input identities, missing metadata,
unsupported formats/targets, reference consistency, request roles, and retention
of translation caveats. Actual current upstream results and proposed fixture
behavior are reported separately.

DuckDB and the pinned synthetic fixture are the qualified execution scope.
Other database backends, authenticated remote sources, production snapshot
admission, concurrent mutation, and cross-process authority are not established.
This work does not change Graft's Reader, durability, or permanent Forget gates.
