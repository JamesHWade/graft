# Portable vocabulary and binding experiment

Issue [#60](https://github.com/JamesHWade/graft/issues/60), executed September 16,
2026. **A local publisher supports both callers without constructing a Graft
store. This establishes a module boundary; it does not establish a need for a
separate ontology package.**

## Runtime evidence

The [runner](../tools/experiments/vocabulary/run.R) passes 18 focused cases on
R 4.6.1, Commons 0.1.0.9000 at
`726a2ed459c2b7c7aebc29539895f04873276b4f`, and datadict 0.1.0 plus the source-built
data-dict CLI 0.0.3 at `0161d460b6eb70d337028f8eddbf2f443bcb8f67`.
[Recorded output](../tools/experiments/vocabulary/observed/results.json) includes
the executable digest and exact content references. Source builds with the same
version number need the commit pin; version 0.0.3 alone is insufficient.

Reproduction command using the required setup attestation:

```sh
export GRAFT_EXPERIMENT_HOME=/tmp/graft-experiment-dependencies
Rscript tools/experiments/setup.R
Rscript tools/experiments/vocabulary/run.R /tmp/graft-vocabulary-results
```

After dependency installation, the runner is offline and credential-free. It
checks the attested CLI digest and package source pins before producing evidence.

| Case | Observed result |
| --- | --- |
| Two independently authored dictionaries | Upstream `validate-spec` and resolved `export-spec` pass for both releases. No dictionary YAML parsing in the publisher. |
| Shared sample identity | A plain R import caller resolves `sample_id` and `specimen` through the same concept; returned values retain different laboratory identity scopes. No chat constructed. |
| Commons caller | Both dictionaries and their detached frames are accepted by public `data_source()`; the generated shared release is accepted by public `context_layer()`. |
| Unknown term, wrong binding kind, ambiguous equivalence | Explicit failures. Multiple concepts for a single field require a new, deliberately supported mapping contract. |
| Renamed/missing field | Binding and imported-data checks reject it; even after repinning a changed valid dictionary, the stale binding fails. |
| Release/content mismatch | Release mismatch and changed vocabulary/dictionary bytes fail independently. |
| Relationship direction | Reversed measurement/sample endpoints fail the declared domain/range check. |
| Qualified assertions | Source, accepted/retracted status, negation, time, scope and direction roundtrip into machine records and generated context. Unexpected qualifiers fail rather than disappearing. |
| Historical replay | Release v2 renames `specimen` to `specimen_id` and clarifies a term. Reopening v1 reproduces its complete published result and context exactly; the old binding rejects the new frame. |
| Unsafe comparison/join | Shared temperature fails due to different units, grain, conditions and scope. Equal sample strings also fail the scope check. The fixture performs no join or conversion. |

The [context](../tools/experiments/vocabulary/observed/context-v1.md) includes
release IDs, term IDs, dictionary digests and qualifiers in the body. Human
explanations and exact JSON records come from the same validated records. Tests
parse the rendered records back and compare them to the machine representation.

## Ownership learned from the experiment

| Responsibility | Proposed owner and evidence |
| --- | --- |
| Local columns, types, expressions and schema validity | data-dict. Its public resolved export supplies field/type metadata without another parser or evaluator. |
| Stable shared concepts and cross-dictionary bindings | One publisher module, currently `publisher.R`. It validates only its own closed companion format; local dictionary semantics stay upstream. |
| Calculation, data-source and context consumption | Commons public constructors. No private constructors, R6 mutation or generic retrieval packaged as a trusted measure. |
| Exact versions and historical bytes | Artifact storage plus a manifest. The publisher returns vocabulary/binding/dictionary IDs and SHA-256 values; it does not preserve content by itself. |
| Reuse approval, access and join/comparison authority | Host policy and separately supported validation. A common term is only evidence for discovery. |

This is roughly 400 lines of experiment publisher code plus roughly 340 lines of
runner/assertions after formatting. That glue must be counted in any architecture
comparison: neither Commons nor data-dict supplies this exact companion contract
through its current public R interface. A shared module is justified by the two
callers; extracting a separately distributed package would still require a
maintained format, compatibility policy and additional real consumers.

## Upstream boundaries and limitations

- data-dict's [resolved export](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/site/export.md)
  already supplies local structural relationships, canonical types and glossary
  content. This experiment adds cross-dictionary stable concept bindings outside
  those authored schemas. It introduces no `graft:` extension or expression
  grammar. The [R wrapper](https://github.com/tidyverse/data-dict/blob/0161d460b6eb70d337028f8eddbf2f443bcb8f67/r/R/binary.R)
  exposes the CLI; the successful runtime calls are the evidence for its use here.
- Commons documents its [public data-source interface](https://github.com/posit-dev/commons/blob/726a2ed459c2b7c7aebc29539895f04873276b4f/pkg-r/R/data-source.R)
  and marks object internals private. The fixture only calls the exported
  constructors. Constructor acceptance does not prove model retrieval or semantic
  reasoning; #62 must test the real public model/tool roundtrip separately.
- Commons [strips frontmatter when constructing context](https://github.com/posit-dev/commons/blob/726a2ed459c2b7c7aebc29539895f04873276b4f/pkg-r/R/context-layer.R).
  IDs and qualifiers are therefore body content. Context prose remains
  descriptive; it cannot enforce eligibility or authorization.
- Spec validation, binding validation and the plain importer's field checks do
  not prove data-value validation. The companion's grain/condition/scope fields
  are explicit author claims. The comparison guard only rejects this fixture's
  mismatches; it is not a general comparability proof, unit conversion system or
  identifier reconciliation service.
- The example has no inference, synonym-based resolution, recursive ontology
  imports, distributed release registry, or production privacy/Forget proof.
  Aliases are published for discovery and never silently treated as equivalence.

**Decision input:** Keep this as one tested publisher while #59/#62 establish
artifact and memory behavior. The vocabulary use case alone does not require the
existing Graft ledger. An artifact module can retain these published releases and
references regardless of whether Graft survives.
