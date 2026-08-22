# Graft

Graft governs knowledge proposed, reviewed, and accepted for use by
people and agents.

## Language

**Answer**: One completed, text-bearing assistant response within a
chat. Trust is classified independently for each answer. *Avoid*: Chat
result, conversation result

**Citation**: An explicit excerpt in an answer that can be matched
deterministically to text returned by a successful Graft read. *Avoid*:
Tool use, source mention

**Accepted boundary**: The exact point in the ordered history of
accepted knowledge against which a read was evaluated. *Avoid*: Current
state, latest data

**Receipt**: Data accompanying a Graft result that identifies the
accepted boundary used for that result. *Avoid*: Metadata, timestamp

**Verified answer**: An answer whose evidence comes exclusively from
governed calculations with valid receipts.

**Cited answer**: An answer whose weakest evidence path is a successful
Graft read supported by an independently matched citation.

**Untrusted answer**: An answer that lacks sufficient governed or
independently matched evidence, or whose evidence path includes a
failure or unknown source.

**Verification**: Deterministic classification of an answer’s recorded
evidence path and receipts. It is neither fact-checking nor
authentication of stored identities. *Avoid*: Fact-check, proof
