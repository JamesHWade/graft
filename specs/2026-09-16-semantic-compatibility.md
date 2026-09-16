# Commons and data-dict semantic compatibility

Issue: [#61](https://github.com/JamesHWade/graft/issues/61).

## Result

**Reuse both packages, but do not claim one compiler yet.** The offline experiment
passes 38 checks against installed development sources. Five real Commons model
tool calls compute over the same Parquet bytes validated by data-dict. A concrete
counterexample remains: data-dict accepts an R-language definition that Commons
rejects. No additional Graft parser, CLI bridge, or evaluator was implemented.

Run [the fixture](../tools/experiments/semantic-compatibility/README.md).
[Recorded results](../tools/experiments/semantic-compatibility/observed.json) include
runtime versions, SHA-256 input identity, individual checks, and negative-case
messages. Source pins and install instructions are in that README. The two tools
consume one authored dictionary; Commons still recompiles its expressions.

## Observed conformance

| Case | data-dict result | Commons result |
| --- | --- | --- |
| Numeric and enum types, nullable revenue | Spec and data-value validation succeed; typed export available | Constructs from detached frames read from the validated Parquet |
| Aggregate `SUM(revenue)` | Metric/number; DuckDB translation executes to 35 | Real governed calculation returns 35, ignoring null |
| Filter `region = 'EMEA'` | Filter/boolean | Filtered metric returns 15; executed SQL records predicate |
| Row expression `revenue * 2` | Derived/number; translated SQL gives 20,40,NULL,10 | Governed token expansion gives the same values and preserves one missing value |
| Definition dependency `SUM(doubled)` | Direct dependency `doubled` exported | Commons composes the dependency and returns 70 |
| Constant `42` | Metric/number; bare SQL returns 42 per input row | Commons supplies metric query orchestration and returns one row with 42 |
| `SUM(revenue) + revenue` | Valid derived/number | Constructor accepts; grouping by it in a metric call is refused as mixed grain |
| Missing column | Spec validation rejects unresolved reference | Constructor rejects unresolved reference |
| `other.revenue` with an actual second table | Spec validation rejects cross-table expression reference | Constructor also rejects; relationship metadata is not an automatic join expression |
| R-language `!is.na(revenue)` | Spec validation accepts `language: r` | Constructor rejects raw expression at `!` |
| Negative revenue and unknown enum | Data-value report status is nonzero | Constructor still succeeds; data-value validation is a separate operation |
| Profiling those invalid values | `export-data` succeeds | Profiling success cannot establish eligibility for calculation/reuse |

The five tool results come from the real Commons agent, not from the scripted
answer text. Exact result rows, the SQL predicate, missing-value count, and
Commons `A` calculation tags are checked. Results include applied definition
names, DuckDB target and the integer-overflow caveat. That evidence does not
supply persistent artifact identities, vocabulary-release identity, or memory
approval. The host must retain those separately.

The public `datadict::dd_validate_data()` call writes a report and returns status;
a failed dataset is deliberately not an R exception. The fixture checks both
status and the existence of the generated report. `export-data` profiles without
performing value validation. These distinctions are upstream contracts, now
exercised with valid and deliberately invalid data. [R validation interface](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/r/R/validate.R),
[export contract](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/site/export.md).

## Canonical execution boundary

The upstream export provides expression kind, value type, direct column and
definition references, target translations, and translation notes. Constants
still require execution context: a bare expression does not choose one result
row versus one per input row. Sibling-definition translation composition is
explicitly the consumer's job. Mixed-grain metadata is not a first-class exported
flag in this fixture, even though Commons uses it when deciding whether a
definition is a valid grouping dimension. [Export semantics](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/site/export.md),
[Commons compilation boundary](https://github.com/posit-dev/commons/blob/726a2ed459c2b7c7aebc29539895f04873276b4f/pkg-r/R/definition-export.R).

Commons' public `data_source(dictionary = ...)` consumes an authored YAML path;
there is no exported constructor for a resolved data-dict export. Its temporary
compiler explicitly anticipates replacement by an upstream R wrapper, with
remaining needs around backend lowering and grain metadata. The `datadict`
package now exposes the CLI, but existence of that wrapper has not connected the
two execution paths. The observed R-language failure demonstrates a real cost of
that split. [Commons public data source](https://github.com/posit-dev/commons/blob/726a2ed459c2b7c7aebc29539895f04873276b4f/pkg-r/R/data-source.R),
[Commons exports](https://github.com/posit-dev/commons/blob/726a2ed459c2b7c7aebc29539895f04873276b4f/pkg-r/NAMESPACE),
[datadict exports](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/r/NAMESPACE).

**Proposed upstream seam:** a typed, versioned resolved-export object in datadict,
accepted by a public Commons constructor. It should preserve canonical source
language, dependency references, scalar/row/aggregate and mixed-grain metadata,
translations, fidelity/notes and dictionary digest. Commons should retain source
binding, dependency composition, backend execution and invocation provenance.
No new compiler belongs in Graft. DuckDB is runtime-verified here; Snowflake,
Databricks, R and Python target execution are unproved in this experiment. A
canonical typed IR or additional upstream targets would be needed to remove
Commons' separate lowering for backends data-dict does not emit.

## Component ownership

| Capability | Reusable component now | Remaining owner or gap |
| --- | --- | --- |
| Tables and detached source construction | Commons `data_source()` | Host selects and authorizes exact input revisions |
| Narrative/context construction | Commons `context_layer()` | Host generates bounded context from selected artifacts |
| Contract, value validation, resolved export | datadict public R interface and CLI | Host checks validation status and binds input digest |
| Governed dictionary calculations | Commons source constructor + agent | Upstream resolved-export seam remains proposed |
| Authored R calculations | Commons `measure()` and `semantic_layer()` | Keep separate from data-dict definitions and ordinary retrieval |
| Conversation/tool provenance | Real ellmer turns; Commons trajectory interfaces | Host preserves persistent artifact and selected-memory evidence separately |
| Vocabulary release/bindings | No tested upstream owner here | Experiment #60 supplies bounded publisher/validator evidence |
| Retained bytes, revisions and restart | No demonstrated Commons artifact repository interface | Experiment #59 compares explicit storage owners |
| Reuse approval and current access | No inferred authority from calculation labels | Host policy; Reader/Forget production gates remain open |

The public layer objects deliberately hide their state, disable cloning and lock
mutation; application composition should use constructors. Commons' model-facing
tools are expressly private implementation contracts. This experiment's fake
model uses their pinned request schema only as version-specific test data,
through real ellmer dispatch; it neither calls private constructors nor adds a
public facade around them. [Layer ownership](https://github.com/posit-dev/commons/blob/726a2ed459c2b7c7aebc29539895f04873276b4f/pkg-r/R/layer-objects.R),
[Commons public composition and tool disclaimer](https://github.com/posit-dev/commons/blob/726a2ed459c2b7c7aebc29539895f04873276b4f/pkg-r/R/commons.R).

## Limits and disposition

This is local deterministic compatibility evidence, not model-quality, UI,
production authorization or production persistence proof. Upstream SQL was
executed directly for the simple scalar/aggregate cases; the derived dependency
was resolved by Commons, so this does not establish every export consumer is
conformant. Cross-table expression references are unsupported; no joining
adapter was added. Translation notes identify numerical edge semantics beyond
this small null fixture. The full compatibility problem belongs upstream;
#62 can proceed through supported authored-dictionary constructors with exact
input/output manifests and these limitations recorded.
