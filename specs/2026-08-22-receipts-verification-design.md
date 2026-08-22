# Receipts and deterministic answer verification

Date: 2026-08-22
Status: approved design, phase 2 of 3

## Problem Statement

Graft's bounded agent tools return accepted knowledge, but their current
metadata does not identify the exact accepted boundary used by each call. A
later reader can see the active structural schema digest, but cannot reliably
distinguish a live-head read from a pinned read or reconstruct which accepted
batch produced the answer.

Hosts also lack a deterministic way to explain the provenance quality of an
assistant answer. They can inspect an ellmer conversation manually, but they
cannot consistently distinguish an answer based exclusively on governed
calculations from one supported by quoted accepted knowledge or one with no
verifiable Graft evidence.

## Solution

Every tool returned by `graft_tools()` will emit one canonical nested receipt.
The receipt identifies the store, exact accepted boundary, schema, and, when
applicable, governed measure definition used by the call. Live tool calls will
pin their accepted boundary for the duration of each invocation so the result
and receipt cannot race a later commit.

An exported `graft_verify(chat)` will inspect an ellmer chat offline and return
one deterministic classification for each completed, text-bearing assistant
answer. It will label an answer Verified when its evidence comes exclusively
from successful governed measure calls, Cited when its weakest evidence path is
a successful Graft read supported by an independently matched quotation, and
Untrusted otherwise. It will return evidence and diagnostic details for hosts
without prescribing a user interface.

Verification classifies the evidence path recorded in the chat. It does not
fact-check the assistant's prose, cryptographically authenticate receipt
identifiers, or consult a live store.

## User Stories

1. As an agent host, I want every Graft tool result to identify its exact accepted boundary, so that I can retain reproducible provenance with the result.
2. As an agent host, I want one receipt shape across all Graft tools, so that I do not need tool-specific parsing logic.
3. As an agent host, I want receipts to distinguish live-head and pinned reads, so that I can explain how the boundary was selected.
4. As an agent host, I want a live tool result and its receipt to use the same accepted boundary, so that concurrent commits cannot produce misleading provenance.
5. As an agent host, I want pinned tool calls to retain their snapshot identity, so that repeated reads remain attributable to the same immutable boundary.
6. As an agent host, I want history queries with an explicit historical boundary to receipt that boundary, so that the receipt describes the returned history rather than the newer enclosing store head.
7. As an agent host, I want governed measure results to identify the accepted measure definition, so that the calculation can be traced to its reviewed revision.
8. As an agent host, I want schema identity in the receipt, so that I can distinguish structural compatibility from the exact built schema used by a read.
9. As a package user, I want old flat receipt fields removed in favor of one canonical contract, so that the experimental API does not accumulate competing representations.
10. As an agent host, I want one trust label per completed text answer, so that each answer can be rendered independently.
11. As an agent host, I want tool-only and interrupted partial turns excluded, so that internal orchestration is not presented as a completed answer.
12. As an agent host, I want measure-only answers labeled Verified, so that governed calculations are distinguishable from ad hoc evidence paths.
13. As a reviewer, I want a generic Graft read to earn Cited only when the answer contains explicitly matched evidence, so that mere tool use is not mistaken for a citation.
14. As a reviewer, I want citation matching to be deterministic, so that rerunning verification produces the same label.
15. As a reviewer, I want short or coincidental text overlaps rejected, so that ordinary prose does not accidentally become a citation.
16. As a reviewer, I want the weakest evidence path to determine the label, so that one governed calculation cannot bless an unsupported part of the same answer.
17. As a reviewer, I want missing, malformed, or errored Graft results to make the answer Untrusted, so that verification fails closed.
18. As a reviewer, I want non-Graft tools in an answer's evidence window to make the answer Untrusted, so that Graft does not assign trust to evidence it cannot classify.
19. As a reviewer, I want answers with no qualifying evidence labeled Untrusted, so that every completed answer receives an explicit outcome.
20. As an analyst, I want legitimate comparisons across accepted boundaries to retain their evidence label, so that historical analysis is not rejected merely for spanning snapshots.
21. As an analyst, I want truncation reported separately from provenance quality, so that incomplete results are visible without misrepresenting their source.
22. As an agent host, I want stable machine-readable reason codes, so that I can explain labels without parsing display text.
23. As an agent host, I want receipts, citations, tool calls, and diagnostics returned with each label, so that I can build my own rendering and audit experience.
24. As a package user, I want verification to work without network access or telemetry export, so that it remains deterministic, private, and testable.
25. As a package user, I want a zero-row result when a chat has no completed answers, so that empty conversations are ordinary data rather than errors.
26. As a package user, I want invalid API inputs to raise classed Graft conditions, so that failures can be handled programmatically.

## Implementation Decisions

- Tool results have exactly four top-level fields: the bounded result,
  truncation flag, limit, and receipt. Existing flat schema and measure receipt
  fields are removed rather than retained as aliases.
- The receipt is one nested object with store, boundary, schema, and optional
  definition sections. Its shape is identical across all tools; the definition
  section is absent unless the result depends on a governed definition.
- The store section contains the stable store identifier.
- The boundary section contains a kind, committed batch identifier, commit
  order, and snapshot identifier. Live reads use the live kind and omit the
  snapshot identifier. Pinned views use the snapshot kind and include it. An
  empty store has no batch identifier and commit order zero.
- Graft's accepted commit vocabulary remains `batch_id` plus `commit_order`.
  The design does not introduce a second `commit_id` concept.
- The schema section contains both the structural schema digest and build
  digest. These identifiers remain distinct because they answer compatibility
  and exact-build questions respectively.
- A measure receipt adds a definition section containing the measure record
  identifier and accepted definition revision identifier.
- Each invocation of a tool created from a live store captures the current
  snapshot and executes its read through a temporary pinned view. The receipt
  describes that invocation boundary, while a later invocation may observe a
  later commit. Creating the tool set does not freeze the store for the whole
  chat.
- A tool created from an existing pinned view continues to use that view and
  its snapshot for every invocation.
- A history call with an explicit historical boundary reports the boundary
  selected by that call with the history kind and no snapshot identifier, not
  the live or view boundary used to access the store.
- Receipt construction and structural validation are centralized. Individual
  tools supply only their bounded result and any definition or explicit
  historical-boundary override.
- `graft_verify()` accepts an ellmer Chat and uses its ordered turns. It retains
  the package's existing ellmer dependency floor because the required Chat,
  Turn, tool-request, and tool-result interfaces are already available there.
- An answer is a completed, text-bearing assistant turn. Tool-request-only
  turns and interrupted partial turns are not answers and receive no row.
- Each answer's evidence window begins after the previous classified answer
  and ends at the current answer. Tool-only turns may occur inside that window.
  Tool results are paired to their requests by ellmer's recorded request.
- A successful Graft result is recognized by a supported Graft tool name and a
  structurally valid canonical receipt. This is structural classification, not
  cryptographic authentication of a tool or identifier.
- Citation candidates are explicit quoted spans or Markdown blockquotes. After
  normalizing whitespace, Markdown emphasis, typographic quotation marks, and
  dashes, a candidate must contain at least ten characters and match textual
  data from a successful generic Graft result using a case-sensitive fixed
  match.
- Citation matching searches textual values within the bounded result. Receipt
  fields, tool descriptions, arguments, and unrelated chat text are not
  evidence corpora.
- Every successful generic Graft result in an answer's evidence window is
  treated as a contributing evidence path and requires at least one matched
  citation. The classifier does not ask the model which calls it actually used.
- Verified requires at least one successful governed measure result, no generic
  or non-Graft tool path, no tool error, and valid receipts for every result.
- Cited requires at least one successful generic Graft result, a matched
  citation for every generic Graft result, no non-Graft tool path, no tool
  error, and valid receipts for every result. Governed measure results may also
  be present, but the generic path caps the answer at Cited.
- Untrusted is the fail-closed outcome for no qualifying evidence, an unmatched
  generic result, a non-Graft tool, a tool error, an unsupported or malformed
  trace element, or an absent or invalid receipt.
- Multiple exact boundaries do not lower a label. A mixed-boundaries diagnostic
  records that fact for hosts. Truncated results likewise retain the label and
  add a truncation diagnostic because completeness and provenance are separate
  concerns.
- `graft_verify()` returns a classed data frame with one row per answer. Stable
  scalar columns contain answer and turn indexes, answer text, and a lowercase
  label. List-columns contain reason codes, receipts, matched citations, tool
  calls, and diagnostics.
- The label vocabulary is `verified`, `cited`, and `untrusted`; display methods
  may render the corresponding title-case labels.
- Stable reasons distinguish governed-measure-only evidence, matched citations,
  no evidence, non-Graft tools, tool errors, invalid receipts, and unmatched
  citations. Diagnostics distinguish truncation and mixed boundaries without
  changing the label.
- A valid Chat with no completed answers returns a zero-row verification object.
  Invalid arguments raise a classed Graft validation condition. Trace defects
  attached to an otherwise identifiable answer become Untrusted evidence rather
  than aborting classification of the whole chat.
- The function is deterministic and read-only. It does not connect to a store,
  mutate the chat, depend on OpenTelemetry, or invoke a model.
- The new public function is documented, exported, added to the package
  reference index, and described in the agent-facing vignette. The breaking
  tool receipt contract and answer classifier receive release-note entries.

## Testing Decisions

- Tests exercise public behavior at the two highest practical seams: direct
  invocation of returned tool definitions and offline verification of an
  ellmer Chat. Internal helper tests are limited to compact tables for receipt
  shape validation and citation normalization.
- Every tool is invoked through its returned definition and checked for the
  exact four-field result contract and canonical receipt shape.
- Live-tool tests commit between invocations and show that each invocation is
  internally consistent while the later call can advance to the new boundary.
- Pinned-view tests commit after tool creation and show that the result and
  receipt remain at the original snapshot.
- History tests cover the default boundary and an explicit earlier boundary.
- Empty-store receipt tests cover the absent batch identifier and zero commit
  order.
- Measure-tool tests cover definition identity in addition to the common
  receipt fields.
- No-network ellmer tests construct exported Turn and Content objects, install
  them on a Chat, and verify the public result rather than mocking classifier
  internals.
- The verification matrix covers measure-only, generic-read-only, mixed
  measure and generic reads, multiple generic reads, non-Graft tools, no tools,
  tool errors, malformed receipts, absent receipts, and unsupported trace
  elements.
- Citation tests cover quoted spans, Markdown blockquotes, normalization,
  minimum length, case sensitivity, multiple results, unmatched evidence, and
  accidental unquoted overlap.
- Turn tests cover multiple completed answers, tool-only intermediate turns,
  interrupted partial turns, and chats with no completed answers.
- Diagnostic tests cover truncation, one boundary, and mixed boundaries while
  asserting that diagnostics do not change an otherwise valid label.
- User-facing errors are asserted by class and snapshot so their text remains
  reviewable. Data-frame and receipt contracts use specific structural
  expectations rather than broad truth assertions.
- Existing exact-public-surface tests and agent-tool documentation tests are
  updated to reflect the intentional receipt contract change and new export.
- The full package suite, formatting, documentation generation, package-site
  validation, and R CMD check are required before the implementation is
  complete.

## Out of Scope

- Fact-checking the assistant's prose or proving that every claim follows from
  the cited evidence.
- Cryptographic authentication of tool definitions, tool results, store
  identifiers, batches, snapshots, or revisions.
- Reopening a store to validate historical receipt identifiers.
- Trust adapters or label policies for non-Graft tools.
- OpenTelemetry ingestion, exported trace reconstruction, or telemetry-backed
  verification.
- A host UI, provenance badges, or rendering policy.
- Model prompting or forcing a particular response template beyond recognizing
  explicit quotations and Markdown blockquotes.
- Backward-compatible aliases for the old flat tool receipt fields.
- R-function measures, roxygen measure discovery, provenance permalinks, or a
  Commons data-source adapter; those remain phase 3.

## Further Notes

- The label hierarchy is modeled on posit-dev/commons' deterministic
  provenance classifier, but Graft uses its own public receipt contract rather
  than Commons' private tags.
- Commons requires independently verified quoted evidence before assigning its
  cited outcome. Graft keeps that principle and applies it to text returned by
  successful Graft reads.
- ellmer's public Chat, Turn, ContentToolRequest, and ContentToolResult objects
  are the compatibility seam. Telemetry is unnecessary for an in-process chat.
- The phase-1 measure design remains authoritative for governed calculation
  semantics. This phase changes tool receipts and classifies their recorded use;
  it does not change measure evaluation.
