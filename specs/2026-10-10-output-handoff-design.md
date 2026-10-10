# Completed output handoff proposal

Date: 2026-10-10. Status: proposed upstream contract with a source-only
conformance prototype for [Graft #66](https://github.com/JamesHWade/graft/issues/66).
This document does not add a Graft production export or change consumer contract
4.2.0. The prototype is in `tools/output-handoff/`. Graft is pre-production;
production adoption should replace superseded interfaces directly rather than
retain compatibility wrappers or alternate legacy paths.

## The seam and its ownership

A host needs complete report, table, and image bytes while a producer still owns
them. Model text, an HTML display, a temporary path, and an integrity digest are
insufficient to preserve that content. The handoff module concentrates completion
validation, bounds, byte verification, exact input dependencies, and candidate
publication behind one interface. Commons and deputy supply two adapters at this
seam. Tests observe retained bytes and host decisions through the same interface.

Commons owns analysis, context, SQL execution, and its evidence classification.
Deputy owns tool dispatch, permissions, hooks, asynchronous execution, and its
designated producer policy. Graft owns opaque artifact preservation, exact
revisions, dependencies, selections, and recorded decisions. The host chooses
inputs, artifact identities, required outputs, bounds, review, purpose, eligibility,
and whether a conversation must be replaced after policy changes. This follows
ADRs 0008, 0010, and 0014; it creates no execution engine or expression interpreter.

Deleting the handoff module would force both hosts to reconstruct byte decoding,
failure rules, exact dependencies, and publication order. The adapters only
translate native completed values; they do not repeat storage or review policy.
Graft's `graft_tool()` remains the model-facing reviewed-memory projection. It
intentionally omits binary bytes and is unsuitable as the output retention path.

## Public upstream inventory

The following claims were checked against the sources pinned in `pins.json`.
Commons PR #414 is a draft, so its `trusted()` interface is provisional.

| Public surface | Preservable content | Limitation |
| --- | --- | --- |
| ellmer `ContentToolResult@value`, `@error`, `@extra` | Explicit scalar text or native content objects; a native error is distinct from success | Arbitrary display metadata and R objects are not portable artifacts |
| ellmer `ContentText@text` | Literal UTF-8 text | Report, SQL, table JSON, and raw citation text require explicit host/producer roles; text is not evidence of authority |
| ellmer `ContentImageInline@type`, `@data` | Decoded PNG bytes with explicit media type | Bound encoded and decoded sizes; remote images and uploaded handles require a separate retention contract |
| ellmer `Turn@role`, `@contents`; completed chat history | Literal completed assistant report and raw native contents | Partial streamed text is not a completed turn; final prose cannot substitute for a designated tool result |
| Commons draft `trusted()$measure()` | The measure's original return value, including an explicitly authored `ContentToolResult` | A raw data frame/ggplot is not itself a portable handoff; the producer must materialize explicit content |
| Commons draft `$metrics()` / `$calculation()` | Result value | These methods return `$result`, dropping prepared SQL and other execution metadata |
| Commons draft `$context()` / `$describe()` / `$search()` | Text projection | These are not complete structured provenance envelopes |
| Commons `measure()` and `semantic_layer()` | A public place to author an explicit completed producer value | Rendered tables, private handles, and `extra$data` are not a stable lossless table export |
| Deputy `TrustedResults()` / `result_trusted_results()` | Original designated tool value before model projection/offload, plus IDs, converted arguments, and tool fingerprint | The event records production, not successful host delivery or review |
| Deputy `Agent$run_async()` / `AgentResult$stop_reason` / `result_is_success()` | Explicit runtime completion outcome | A completed run can still lack required outputs; delivery failure must be checked separately |

The earlier [#62 experiment](https://github.com/JamesHWade/graft/issues/62),
documented in `specs/2026-09-16-commons-roundtrip.md`, preserved report text, a
structured table explicitly exported by sandboxed R, decoded inline PNG,
calculation SQL, evidence labels, and raw citation text. It retained a 16-artifact
exact dependency closure. The structured JSON export and the scripted model's
tool names were experiment protocol, not public host interfaces.

The new fixture uses a measure that explicitly returns report text, structured
table JSON, and an inline PNG. Any SQL or raw citation strings in this synthetic
producer are supplied explicitly as producer evidence. It does not scrape an
HTML table, recover private `gt` data, reconstruct SQL from model prose, claim
that the fixture's labels were issued by the Commons chat classifier, or replay
the old sandbox/model export protocol as a product interface.

## Proposed neutral envelope

The following wire shape is a **proposal**, not an existing Commons or deputy
export. The prototype version is `graft-output-handoff/0.1`.

```json
{
  "schema": "graft-output-handoff/0.1",
  "operation_id": "producer-completion-17",
  "state": "complete",
  "producer": {
    "name": "analysis_measure",
    "version": "pinned-source",
    "evidence": {"commons_tag": "A", "sql": null, "raw_citations": []}
  },
  "errors": [],
  "outputs": [{
    "key": "report",
    "media_type": "text/plain",
    "size": 3,
    "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    "encoding": "base64",
    "data": "YWJj"
  }]
}
```

Each output contains complete owned bytes encoded as base64, or
`encoding: "retained"` and an exact `ref: {"id": ..., "revision": ...}`.
Retained references must resolve in the host-bound store and match the declared
size, media type, and SHA-256. A path, URL, handle, or digest alone is invalid.
Output keys are unique and explicitly bound by the host; the prototype requires
report/table/figure by default. The host may choose a different required set.
Producer fields are bounded plain JSON, never serialized arbitrary R objects.
The prototype emits canonical base64 without whitespace; native image adapters
normalize bounded wrapped or unwrapped producer encodings before building it.

The host supplies the verified exact input selection separately. Retaining that
selection does not prove the producer actually used it; the host must bind the
selection to the real run and assess that evidence. A model cannot
choose a store, artifact prefix, review stream, eligibility callback, or review
decision through the packet. An operation ID identifies a producer completion;
a Commons label describes its evidence path; a Deputy fingerprint identifies a
designated local tool; an artifact reference identifies retained bytes. None
authenticates another or establishes truth or permission.

The producer must not mark `complete` while any required output is still being
written. Failed, cancelled, denied, partial, missing, or delivery-failed outcomes
carry structured errors and do not yield a successful candidate. Missing SQL,
bindings, or citation evidence must be recorded as missing, not invented.
The prototype refuses nonempty errors on a successful packet.

## Candidate publication and review

`retain_completed_output()` is a prototype host interface, not a package export.
It checks the packet, all required bytes and digests, the complete exact input
selection, limits, and fresh host eligibility before preservation. It saves
producer evidence with exact input-root dependencies, preserves each output, and
publishes a root manifest last. The root binds the exact output references,
producer evidence, and input selection identity. Retained output references
remain exact dependencies of that root.

The result is a draft candidate. The host reviews its exact root selection and
calls `graft_accept()` separately. A fresh process then uses `graft_recall()` with
current host eligibility and purpose. `graft_withdraw()` removes current accepted
recall while exact historical reads remain inspectable. Stored R code, SQL, an
evidence label, or executable-looking text remains opaque content and cannot
register a tool or acquire a trusted-calculation label by being saved.

Validation occurs before writes; eligibility is rechecked before root publication.
There is no cross-artifact transaction guarantee for local storage. A failure
after some saves may leave unreferenced draft artifacts, but returns no completed
root. Hosts must not infer success by discovering an orphan. Exact retries reuse
immutable references; a changed byte, dependency, or producer evidence creates a
new revision. This is not exactly-once execution, automatic reapproval, crash
recovery, power-loss durability, or a guarantee against revocation immediately
after a point-in-time eligibility check.

Default prototype limits are 128 outputs, 1 MiB per output, 4 MiB aggregate
decoded output, and 64 KiB metadata. The Graft store's complete dependency closure
bounds apply as well, including the evidence and root metadata bytes. The manifest
does not duplicate binary payloads inside evidence JSON.

## Deputy integration

Use a designated local read-only, closed-world tool with `TrustedResults()`.
The host obtains the original `ContentToolResult` from the public trusted event;
model narration and formatted `tool_end` projections are not retention sources.
The adapter checks a completed `AgentResult`, exactly one requested producer
event, native producer error, and delivery failure before producing a packet.
Producer event IDs, tool fingerprint, and converted arguments remain evidence.

The same Agent can include Graft's read-only reviewed-memory tool. Deputy's strict
producer policy rejects arbitrary model code, delegation, MCP/provider producers,
and unsafe or unannotated tools alongside the designated producer. A Commons
coding session is a separate route. This proposal does not relax that restriction
or bypass Deputy permissions, hooks, approvals, or budgets. A trusted event can
exist even if `on_result` failed; the host must explicitly retry failed delivery.

## Failure and conformance matrix

| Condition | Required host behavior |
| --- | --- |
| Asynchronous producer still running | Wait for explicit completion; no packet/root from partial output |
| Missing/partial output or native producer error | Reject handoff; no completed root |
| Worker exits after handing over owned bytes | Retain those bytes; no dependence on its temporary files |
| Temporary path, remote image, digest without bytes/ref | Reject as unpreserved |
| Oversized encoded/decoded bytes or metadata | Reject before publication under caller/store bounds |
| Incorrect digest, size, media type, or retained ref | Reject; never substitute a newer revision |
| Exact retry / corrected producer result | Same references / new immutable revisions |
| Deputy denied tool or failed producer | No designated completed event can supply a candidate |
| Deputy delivery callback failure | Event alone is insufficient; reject successful delivery |
| Host eligibility removed during handoff | Stop before root publication; orphan drafts may remain |
| Host review withdrawn after acceptance | Fresh recall is withdrawn and contains no bytes |
| Model fabricates report, table, or label | It cannot replace the designated producer value or accept it |

The fixture uses a synthetic localhost OpenAI-compatible SSE transport to make
these tests credential-free. The transport is a test adapter only. It is not an
agent protocol that Graft exposes to applications. Sources are extracted anew
from verified immutable archives, loaded with `pkgload`, and never installed over
the user's libraries. The full fixture requires localhost sockets and R child
processes; a separate core-only run exercises storage/envelope behavior.

## Concrete upstream request

For Commons PR #414, retain the direct trusted-calculation interface, and add a
public completed-output value or extraction operation that supplies explicit
structured table bytes, images, report text, SQL/bindings when available, labels,
raw citation text, and completion/error states. Use that one value behind the
agent display, direct trusted methods, and host handoff adapters. Keep missing
evidence explicit. Do not require private tool constructors, display scraping,
model-generated export code, or access to private table handles.

For deputy, keep `TrustedResults` as the designated-producer seam. A documented
completed-output adapter can consume the original event value and delivery
outcome without adding a Graft dependency or weakening producer restrictions.
Normalize rich output for display only after the host has received the complete
value. A portable envelope can be consumed from Python without serializing R/S7.

Before production adoption, agree the upstream versioning and structured-output
contract, exercise a real Commons analysis stream and a deputy consumer under
their actual host permissions, and specify asynchronous cancellation/delivery
retry guarantees. The conformance prototype supplies evidence for that discussion;
it does not make draft Commons interfaces stable or settle application policy.

## Primary sources

- [Commons interoperability issue #410](https://github.com/posit-dev/commons/issues/410)
  and [draft PR #414](https://github.com/posit-dev/commons/pull/414).
- [Pinned Commons trusted methods](https://github.com/posit-dev/commons/blob/c1d97d6f5dea094580213198842173af5d299c47/pkg-r/R/trusted.R)
  and [measure contract](https://github.com/posit-dev/commons/blob/c1d97d6f5dea094580213198842173af5d299c47/pkg-r/R/measures.R).
- [Pinned deputy trusted-results policy](https://github.com/JamesHWade/deputy/blob/0ab9862330627b053c4a9870bd5f1300d0829768/R/trusted-results.R)
  and [result/event contract](https://github.com/JamesHWade/deputy/blob/0ab9862330627b053c4a9870bd5f1300d0829768/R/agent-result.R).
- [ellmer ContentToolResult](https://ellmer.tidyverse.org/reference/ContentToolResult.html)
  and [inline images](https://ellmer.tidyverse.org/reference/ContentImageInline.html).
