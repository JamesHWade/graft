# Minimal knowledge conventions: proof and disposition

Scope: #44, with executable host evidence for #40 and a documentation handoff to
#42. Baseline: Graft main at `87d8ddd`, after PR #43. This is a design/proof
report, not a new schema standard or a Tempest/Rill integration claim.

## Disposition

Use application-owned data-dict schemas and existing Graft APIs. Neither a new
R KnowledgeRecord class nor a companion YAML contract is justified by this
slice. Narrative content survives ordinary string fields, explicit kinds and
purposes, flat tags, and normalized evidence records. The same public ToolDefs
compose with three current hosts. The demonstrated Graft bug is narrower:
verification must decode ellmer's JSON tool-result envelope before validating
its receipt and matching citations.

This does not decide access, eligibility, erasure, or general dependency
invalidation. Those have observable enforcement requirements beyond storing
fields. Keep #45–#48 as the next design frontier; implement their shared
mechanisms only after the independent consumer contracts demonstrate a need.

## Representation and enforcement matrix

The upstream columns below separate the published specification from executed
producer behavior. `tests/testthat/test-data-dict-narrative.R` is the executable
probe; the shipped resolved fixture keeps ordinary R use independent of a CLI.

| Feature | Upstream representation | Upstream validation | Graft enforcement | Application responsibility |
|---|---|---|---|---|
| Unicode, multiline Markdown | String data; Markdown descriptions/details | Type/required checks; no claim-level truth | Text and revisions retained | Interpret prose, render it appropriately |
| Epistemic kind and purpose | String/enum columns | Enum membership | Enum membership, requiredness | Choose domain vocabulary and allowed uses |
| Flat tags | `list(string)` | Element types; Parquet encoding depends on producer | Flat list storage/validation | Define tag meaning |
| Evidence links | Related scalar ID columns | Referential checks | Existing or co-proposed target IDs | Exact Document version, anchor validity, support strength |
| Nested struct/list | Supported by the format and both export probes | Spec checks; current validator descends into nested fields | `graft-table-v1` rejects structs and nested lists | Normalize related records first; #39 owns widening design |
| Identity | Named/numeric/composite keys are representable | Key checks have type-dependent limits | One scalar string primary key named `id`, globally unique IDs | Stable domain IDs; no implicit numeric-key conversion |
| Assertions | Parsed expression plus referenced columns | Baseline CLI 0.0.1 does not enforce the probe; release 0.0.3 rejects the same violation | Assertion prose/metadata is not executed at acceptance | Explicit domain validation before host acceptance |
| Restricted fields | `display: restricted` | Presentation policy, not a row-level permission | Public reads/tools omit restricted fields | Reader identity, private source access, authorization |
| Analytical definitions | Named expressions in the current spec | Version-dependent expression validation | Accepted `GraftDefinition` records and governed evaluation | Distinguish definitions from narrative and trusted file measures |
| Archive / eligibility | Can represent status values | Values/types, not consultation policy | Archived teaching record remains readable/searchable | Enforce automatic-consultation eligibility, #46 |
| Forget | No erasure semantics | Not a dictionary check | Ordinary history/delete is not permanent erasure | Purge and backup/restore contract, #48 |

Release 0.0.3 additionally renders descriptions as HTML and supplies expression
translations; separate frozen exports retain that build distinction.

The baseline exporter rejects table `definitions` in YAML, although current
upstream documentation describes them. Named Definitions use the existing
public `graft_plan()`/`graft_ingest()` path, covered separately in
`test-measures.R`.
Do not conflate a producer release, a Graft adapter profile, and current upstream
capabilities. The assertion probe uses scalar Parquet fields; the baseline
producer misclassified a DuckDB-written list column as struct, so that probe is
not evidence of list-Parquet interoperability. Flat-list Graft storage is
verified independently.

## Knowledge record semantics

A Knowledge record in this report means an application-selected domain record
with stable identity and accepted Graft revisions, not a new Graft class.
Acceptance says the host accepted the record for its declared purpose; it does
not establish factual truth, eligibility, access, or execution authority.

| Case | Content and purpose | Evidence and authority |
|---|---|---|
| Tempest conclusion | Provisional synthesis used in a later research task | Tempest owns claims, spans, support, source identities and promotion validation |
| Rill interpretation | A Reader-accepted interpretation carried forward | Rill owns immutable Document anchors, Reader binding and acceptance meaning |
| Reader preference | Reading-selection preference, explicitly requested | No fabricated citation; preference is not evidence about a source |
| Unresolved question | An open question used for future investigation | Acceptance does not turn the question into an established assertion |

`inst/examples/narrative-knowledge.R` demonstrates these distinctions with
synthetic teaching records. It does not map or replace Tempest's promotion
schema. A support record holds one source link and anchor; multiple supports
are related records rather than nested fields or comma-separated IDs. The
preference deliberately has no support record. A model-proposed owner/status
field cannot authorize anything.

Tempest already has a closed promotion bundle and public
`tempest_promotion_bundle()`, `tempest_graft_plan()`,
`tempest_promotion_receipt()`, and `tempest_knowledge()` boundaries. Preserve its
Claim/Source/EvidenceSpan/Support/program identities and the 1,000-record
knowledge bound. Inspecting those contracts is not the completed-product,
restart, unchanged-day and correction proof owned by #50.

Rill ADRs 0002/0003/0004/0007 already define Reader Memory, Reading Artifacts,
Conversation retention, immutable Documents and host approval. #51 owns the
runtime implementation. A shared Feed does not make a private Document public.

## Reuse basis semantics

A snapshot identifies an accepted store boundary, not the selected records.
A minimal application-owned basis is the snapshot plus a bounded list of
selected record IDs, their exact revision IDs, and explicitly selected evidence
closure. Record schema/build and store identity through the snapshot; retain
application-specific source version and anchor meaning in domain records.

The worker regression serializes a complete four-record selection (interpretation,
preference, support and source), closes the connection, opens a fresh read-only store in a
separate R process, rebinds the snapshot, and checks every selected revision and
payload. This proves a bounded reconstruction recipe, not an exported basis
validator. It does not send a live DuckDB connection across processes.

Keep this complete basis on a no-change day. A later change receipt must not
replace it. #45 must settle missing/deleted/inaccessible references, exact versus
logical links, bounds, dependency invalidation and tombstones. #46 controls
eligibility after Archive; #47 controls current access after pinning; #48 makes
Forgotten content unavailable even through an old basis. Serializing identifiers
never grants those permissions.

## Alternatives considered

1. **Application schemas plus existing APIs:** sufficient for this proof. Domain
   semantics remain explicit and tested where the application owns them.
2. **Minimal R binding:** defer. Two differently named record types or repeated
   function calls alone do not demonstrate a shared executable mechanism.
3. **Versioned companion:** defer. No demonstrated shared operation requires
   dictionary/build binding, canonical digests, field selections and a second
   validation lifecycle. Unknown root `graft:` keys are rejected by the actual
   upstream producer; they are not an available extension point.

Retain ADRs 0002/0003: Graft Definitions are named compatible expressions;
Commons file measures are separately owned trusted R functions. Accepted prose
or saved code cannot register itself as an executable tool.

## Evidence and bounded follow-through

- Shipped YAML and resolved JSON: `inst/extdata/narrative-knowledge.*`.
- Offline example and fixture: `inst/examples/narrative-knowledge.R`.
- Runtime storage checks: `test-narrative-knowledge.R`.
- Complete selection and worker checks: `test-reuse-basis.R`.
- Real producer export/nesting/extension/assertion checks:
  `test-data-dict-narrative.R` (optional CLI; no downloads in tests).
- Actual Chat, Deputy Agent and dsprrr ReAct loops: `test-host-composition.R`.
  Local HTTP/SSE fixtures serve only synthetic content on loopback. No API keys,
  remote providers or user records are used.
- JSON normalization and ambiguous/malformed envelope regressions: `test-verify.R`.

The next logical work is #45/#46's exact selection and eligibility contracts,
then #47/#48 before Rill rollout. #39 receives actual structural needs. #50 and
#51 remain separate real-application proofs, feeding #41. #49/#52 are later
content/procedure explorations. #42 still owns the broader visual/navigation
refresh and published-site verification. #53 owns the demonstrated ellmer
implicit list-result deprecation and its public return compatibility decision.

Primary references: [data-dict specification](https://data-dict.tidyverse.org/spec.html),
[validation](https://data-dict.tidyverse.org/validation.html),
[data-dict 0.0.1 source](https://github.com/tidyverse/data-dict/tree/d794c9616f7803199432e9b31b519216aa78d1b0),
[data-dict 0.0.3 release](https://github.com/tidyverse/data-dict/releases/tag/v0.0.3),
[Graft ADRs](https://github.com/JamesHWade/graft/tree/main/adr),
[Tempest promotion contracts](https://github.com/JamesHWade/tempest/blob/main/R/promotion-types.R),
[Tempest knowledge](https://github.com/JamesHWade/tempest/blob/main/R/knowledge.R),
[Rill ADRs](https://github.com/JamesHWade/rill/tree/main/docs/adr).
