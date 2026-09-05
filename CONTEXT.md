# Graft

Graft governs knowledge proposed, reviewed, and accepted for use by people and
agents.

## Language

**Answer**:
One completed, text-bearing assistant response within a chat. Trust is
classified independently for each answer.
_Avoid_: Chat result, conversation result

**Citation**:
An explicit excerpt in an answer that can be matched deterministically to
text returned by a successful Graft read.
_Avoid_: Tool use, source mention

**Accepted boundary**:
The exact point in the ordered history of accepted knowledge against which a
read was evaluated.
_Avoid_: Current state, latest data

**Reuse basis**:
A host-selected, bounded set of exact accepted record revisions and its
declared evidence dependencies, retained with the snapshot that resolves them.
A change receipt does not replace this complete selection.
_Avoid_: Latest receipt, current memory

**Consultation eligibility**:
The application's current decision that selected knowledge may be used for a
task. Eligibility is separate from acceptance, historical inspection, access,
and factual truth; a snapshot does not freeze it.
_Avoid_: Trusted status, snapshot permission

**Commons source**:
A detached query copy of public accepted knowledge from one accepted boundary,
materialized atomically for Commons. It includes typed empty tables and is
neither a live Graft store nor a trust bridge.
_Avoid_: Live source, Commons store

**Public table**:
A queryable projection of accepted knowledge defined by the contract, either a
class projection or a normalized relation projection. System, sensitive, and
internal tables are excluded.
_Avoid_: Database table, contract class

**Definition**:
An accepted, named, data-dict-compatible expression over one public table. A
definition is a metric, filter, or derived value that may participate in
semantic evaluation. Commons is a consumer of this compatibility contract,
not its owner.
_Avoid_: Governed measure, calculation record

**Metric**:
An aggregate definition evaluated with same-table dimensions, filters, and
simple predicates.
_Avoid_: Measure, calculation

**Semantic evaluation**:
A read-only composition of one or more metrics with definitions and public
scalar columns over one public table at one accepted boundary.
_Avoid_: Measure call, semantic query

**File measure**:
A trusted, human-authored R function loaded by Commons outside Graft's
plan, review, and commit lifecycle.
_Avoid_: Definition, stored measure

**Agent interaction**:
The Commons-style loop in which an agent prefers governed calculations and may
use separately labeled fallback paths. Graft extends this interaction with
accepted definition history, exact boundaries, and receipts; it does not make
prompt obedience an invariant.
_Avoid_: Verified reasoning, constrained agent

**Receipt**:
Data accompanying a Graft result that identifies the accepted boundary used
for that result.
_Avoid_: Metadata, timestamp

**Verified answer**:
An answer whose evidence comes exclusively from governed calculations with
valid receipts.

**Cited answer**:
An answer whose weakest evidence path is a successful Graft read supported by
an independently matched citation.

**Untrusted answer**:
An answer that lacks sufficient governed or independently matched evidence,
or whose evidence path includes a failure or unknown source.

**Verification**:
Deterministic classification of an answer's recorded evidence path and
receipts. It assesses neither prompt obedience nor semantic fidelity and is
neither fact-checking nor authentication of stored identities.
_Avoid_: Fact-check, proof
