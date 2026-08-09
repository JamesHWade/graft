# Data-dict parity spike

## Decision

Support `data-dict.yaml` as an alternative table-contract provider and
interchange adapter for Graft. Keep the canonical `.graft.json` runtime
contract and the Graft revision ledger as separate concerns. data-dict never
becomes the ledger or an acceptance path, and the upstream CLI is not a
required runtime dependency.

The fixtures target upstream commit
[`d794c9616f7803199432e9b31b519216aa78d1b0`](https://github.com/tidyverse/data-dict/commit/d794c9616f7803199432e9b31b519216aa78d1b0),
whose specification reports version `0.1.0`. The commit pin is authoritative:
the pre-1.0 project can make breaking changes without a stable release.

Two similarly named versions cross the adapter boundary. The `$version` in
YAML is the source-spec version accepted by the authoring toolchain. The
top-level `$version` emitted by `export-spec` is the resolved JSON export-format
version. Both are `0.1.0` at the pinned commit, but Graft records them
separately and does not treat one as evidence for the other.

## Fixtures

- `personinfo/data-dict.yaml` is the small parity case. It maps people and
  organizations directly and normalizes the multivalued `employed_by`
  reference into a bridge table.
- `tempest/data-dict.yaml` is the boundary case. It covers enums, units,
  assertions, table relationships, polymorphic references, provenance-adjacent
metadata, restricted display policy, and Graft-specific identity and
statement semantics. Its synthetic `source.access_notes` field exists only
to test restricted-display policy propagation; it is not inferred from the
Tempest LinkML fixture.

Both fixtures omit `source.parquet`. They are contract fixtures, not claims
that corresponding Parquet files exist. A later data-validation spike should
generate projection files explicitly and test them separately.

The `graft-table-v1` profile requires a non-empty top-level dataset `name` and
an explicit type for every YAML column. Table and column names must produce
non-empty, case-insensitively unique Graft projection names and unambiguous
`table.column` contract keys; table projections cannot use the reserved
`_graft_` prefix. Every table has one public scalar string primary key named
`id`; accepted ID values must be non-empty after trimming and globally unique
across all tables. Foreign keys must be scalar strings that target a concrete
table's primary `id`. Bridge tables therefore receive explicit stable IDs even
when a composite key would be natural. Scalar `number(id)` and
`list(number(id))` columns are rejected anywhere in the contract because their
numeric equality cannot be represented as exact text; authors must use quoted
string codes. This is a deliberate compatibility profile, not a general
restriction of data-dict.

## Implemented boundary

`graft_schema()` now accepts either `data-dict.yaml` or resolved
`data-dict export-spec` JSON. YAML invokes only `export-spec` on an explicitly
installed CLI selected through `graft.data_dict_cli`,
`GRAFT_DATA_DICT_CLI`, or `PATH`; it does not run `validate-meta` or
`validate-data`. Resolved JSON does not require the CLI and must be treated as
trusted export-spec build input. Normal package use never downloads or builds
Rust.

Both inputs compile into the same validated Graft v2 manifest. The manifest
records the export-format version, adapter version, a sanitized public
dictionary, mapping counts, profile defaults, and known semantic limits. YAML
also records its separate source-spec version, the observed CLI version, and
the executable digest. Graft captures the source bytes once; YAML preflight,
source-spec inspection, CLI `export-spec`, and the source-byte digest that
feeds the source/build fingerprints all use that private snapshot, with YAML
expression evaluation explicitly disabled. Graft also hashes the executable
before `export-spec`, verifies the digest after that command, runs `--version`,
and verifies the digest again; a replacement during either operation fails
compilation. The optional revision is caller-supplied and is not verified
against that binary. Resolved JSON has no observed CLI
version or digest and cannot establish the YAML source-spec version. Provider
metadata omits graft's configured CLI path, original input path, and private
snapshot path, but retained public contract text is not scrubbed for arbitrary
path-like strings. Provider metadata is allowlisted: unknown or duplicate
fields fail instead of being silently removed, and YAML-only CLI provenance
must be absent for resolved JSON.

The public dictionary is not the full resolved export. Graft removes every
column `examples` and `range`, the dataset `origin`, every table `origin`, and
every table `source` locator. The raw source still contributes to source and
build digests, so redacted changes remain detectable without placing their
values in cleartext. Those digests still permit equality tests and offline
guessing of low-entropy values; they are not a secrecy boundary. Other retained
schema fields are public contract metadata, including descriptions, glossary
terms, enum values, units, assertions, relationships, and `display` policy.
Those fields can still expose observed or sensitive values that an author
embedded manually; the adapter is not a general metadata scrubber.

The adapter rejects `export-data` rows and column profiles, including nested
profiles, so those export-data-derived observations cannot enter the runtime
contract automatically. Shape and version checks cannot authenticate arbitrary
JSON as a genuine upstream export; provenance for a committed resolved artifact
remains a build-system responsibility. Resolved dataset versions retain the
upstream lexical contract: three-component version numbers, valid ISO 8601
calendar dates, or opaque hashes. A lexical guard checks JSON number tokens
before lossy numeric conversion. It rejects every token whose magnitude exceeds
`2^53 - 1` and any lexically nonzero token that would overflow to a non-finite R
value or underflow to zero; exact codes belong in strings.

Selecting a data-dict source in `graft_schema()` is the explicit choice to use
the `graft-table-v1` defaults: every table is a node class, its primary `id` is
required, public scalar text and enum fields are searchable, and Graft-specific
roles or statement shapes are not inferred.

## Observed parity

The real upstream CLI at the pinned commit validated and exported both
fixtures. The resulting Graft contracts produced this comparison:

| Fixture and provider | Classes | Slots | Enums | List relations | Statement classes |
|---|---:|---:|---:|---:|---:|
| PersonInfo LinkML | 2 | 6 | 0 | 2 | 0 |
| PersonInfo data-dict | 3 | 9 | 0 | 1 | 0 |
| Tempest LinkML | 10 | 49 | 6 | 1 | 2 |
| Tempest data-dict | 8 | 66 | 9 | 0 | 0 |

The PersonInfo difference is intentional: `employed_by` becomes a bridge
class with two scalar foreign keys, while `aliases` remains a list relation.
The Tempest result demonstrates the boundary: flat table structure, supported
types, enums, descriptions, units, and scalar foreign-key validation survive,
but statement roles, inheritance, and graph-specific semantics do not.
Per-column data-dict enums also become local Graft enum contracts rather than
shared LinkML enums.

## Feature and loss matrix

| Graft or LinkML feature | Data-dict representation | Parity | Consequence |
|---|---|---:|---|
| Concrete class | Table | Exact for flat record classes | Class inheritance is not retained. |
| Scalar slot | Column | Structural mapping for supported types | LinkML type URIs are not retained, and candidate values use Graft's R-facing coercion semantics. |
| Required identifier | `primary_key` | Partial; Graft is stricter | Graft additionally requires a public scalar string named `id`, rejects empty or whitespace-only values, requires IDs to be globally unique across tables, and rejects a primary `id` that is also a foreign key. |
| Required slot | `required` | Partial; Graft is stricter | Graft treats empty or whitespace-only scalar strings and empty lists as missing, and rejects missing collection elements; data-dict requiredness governs container nullness. |
| Enum | `enum` plus `values` | Exact for non-empty string values | Empty and whitespace-only values are rejected; global enum identity and permissible-value URIs are lost. |
| Scalar object reference | `foreign_key` plus resolved reference | Partial | Both declarations must agree. Graft validates a scalar string target ID in one concrete table, but does not create a graph traversal edge. Abstract and polymorphic ranges are not expressible. |
| Multivalued scalar | `list(type)` | Exact for value shape | Ordering metadata beyond list order is unavailable. |
| Multivalued object reference | Bridge table | Structural approximation | Each bridge row is a node with a public stable ID and scalar validated foreign keys, not a graph edge. Predicate URI and original slot ownership become descriptive only. |
| Numeric bound | Representative `range` or SQL-like `assert` | Redacted or preserved, not enforced | Representative ranges are removed from the public manifest. Assertion source remains public review metadata but is not executed. Neither becomes a Graft acceptance bound. |
| Pattern | `SIMILAR TO` assertion | Preserved, not enforced | Assertion source text remains available for review but is not translated into a Graft regex constraint. |
| Non-primary uniqueness | `unique` | Preserved, not enforced | Only the primary `id` participates in Graft identity validation. |
| Relationship join and cardinality | `relationship` | Partially mapped | A resolved scalar foreign key validates its target; cardinality, aliases, conflicts, range joins, and multi-column join pairs remain metadata. |
| Unit and number measure | `number(quantity)` plus `units` | Preserved as metadata | Units are retained as strings and supported numeric types use Graft's double representation. |
| Date-time zone | `time_zone` | Restricted and enforced | Omission requires RFC 3339 `Z` or `±HH:MM` on every character value. `UTC` requires a zoneless value interpreted as UTC. Both allow at most six fractional digits; `POSIXt` is accepted, while `Date`, `naive`, and named-zone contracts are rejected. |
| Candidate type validation | Canonical type plus Parquet metadata | Mapped with different coercion | Graft applies its R-facing coercion rules to candidate values, not upstream Parquet metadata validation. |
| Sensitive display policy | `display: restricted` | Mapped to default retrieval policy | Restricted payload fields are omitted from default Graft APIs; primary IDs remain public and cannot be restricted. |
| Label, description, details | Corresponding descriptive fields | Preserved as public metadata | Values are not content-scrubbed; Markdown and rendering remain consumer concerns. |
| Dataset version | `version` | Preserved as public metadata | It is not an immutable accepted revision. |
| Dataset and table origins; table source locators | `origin` and `source` | Redacted | Raw values are absent in cleartext but bind source and build digests, which permit equality tests and offline guessing of low-entropy values. |
| Data rows and profiles | `export-data` rows and column profiles | Rejected | Graft blocks export-data-derived observations from entering automatically; retained public metadata can still contain values embedded manually. |
| Numeric identifier type | `number(id)` or `list(number(id))` | Rejected | Numeric codes may be integer or floating point and cannot be lowered to exact text without changing equality. Authors use quoted strings. |
| Unsafe resolved JSON number | Magnitude greater than `2^53 - 1`, or a lexically nonzero token that converts to non-finite or zero in R | Rejected | The lexical guard fails before accepting overflow or underflow from lossy R numeric conversion. |
| External identifier annotation | Column description/details | Descriptive only | Normalization algorithm and version are lost. |
| Class role, statement shape, label slot, search slots | Table details | Descriptive only | Graft dispatch and retrieval policy cannot be reconstructed. |
| ID policy, origin-key slots, qualifier slots | Table details | Descriptive only | Matching, deterministic identity, and qualifier behavior are lost. |
| Polymorphic statement reference | Plain string with explanation | Loss | One data-dict foreign key targets one table. |
| LinkML inheritance and URI semantics | None | Loss | Data-dict is table-native rather than an ontology or graph type system. |
| Revision ledger and accepted heads | None | Out of scope | Graft remains the authority for accepted content. |
| Provenance, read-only plans, stale checks, atomic commit | None | Out of scope | Data-dict cannot replace Graft's acceptance boundary. |
| History, bounded retrieval, projections, and OKF review | None | Out of scope | These remain Graft services over accepted revisions. |

## Public metadata and redaction

The adapter publishes dataset, table, and column names; labels; descriptions;
details; dataset version; enum values; units; glossary terms; relationships;
join metadata; assertion source text; and display policy. This is public
contract metadata even when a column uses `display: restricted`; that policy
protects accepted payload values, not the schema description. Retained fields
can still disclose manually embedded observed or sensitive values.

The public manifest strips every column example and representative range,
dataset and table origins, and table source locators. The raw values still
affect source and build digests. The resolved export's `$version` is retained
specifically as the export-format version. YAML compilation separately records
the YAML source-spec `$version`, observed CLI version, and guarded executable
digest; an optional revision is supplied by the caller, not discovered or
verified. Resolved JSON has no observed CLI provenance or trustworthy
source-spec version.

Graft-only metadata must not silently disappear. The compiled manifest contains
a structured `dictionary$not_enforced` report for known defaults and losses,
including inheritance, URIs, role, identity policy, identifier values,
requiredness, external identifier normalization, search policy, unique
constraints, representative ranges, assertions, relationship cardinality and
joins, graph projection, profiles, restricted time-zone support, units,
`number(id)`, type-validation semantics, origin keys, qualifier slots,
polymorphic references, and statement-shape invariants. The report supports
review; it is not an exhaustive proof of semantic equivalence.

## Integration seam

Use the upstream CLI's `export-spec` JSON as the initial boundary. It resolves
types, implied constraints, references, relationships, aliases, and assertion
column dependencies. YAML input requires every column to declare a type before
export because upstream omits untyped columns. Reimplementing the evolving YAML
lowering rules in R would create a second, unversioned interpretation.

The implementation:

1. captures the input bytes once, invokes a caller-supplied
   `data-dict export-spec` on the YAML snapshot, or reads the trusted resolved
   JSON snapshot;
2. parses `export-spec` JSON into a neutral adapter model;
3. translates that model into Graft's compiled contract;
4. stores the contract together with explicit preservation and loss reports;
5. compares both fixtures with their LinkML-derived Graft manifests; and
6. keeps the Graft revision ledger authoritative regardless of schema provider.

## Pinning and distribution constraints

- Pin the full upstream Git commit, not only spec `0.1.0` or Cargo `0.0.1`.
- Record the executable digest in CI and any generated YAML-derived contract.
  Graft verifies that the selected executable remains unchanged across
  `export-spec` and `--version`; treat the optional revision as caller-supplied
  build provenance.
- Do not download or compile the executable implicitly during normal package
  use.
- Keep the integration optional while installation requires a Rust toolchain
  or a separately supplied binary.
- Prefer subprocess JSON exchange to Rust FFI during the spike; it is easier
  to isolate, pin, and remove.
- Test Linux, macOS, and Windows behavior before advertising support.
- Do not vendor or redistribute upstream code until the repository contains a
  complete license file. Cargo metadata declares MIT, but the pinned repository
  has no recognized root license file or tagged release.
- Treat Arrow and Parquet as upstream implementation dependencies rather than
  adding them to Graft's R runtime unless projection validation proves worth
  the distribution cost.

## Adoption gates

Do not replace LinkML or add a required runtime dependency until all of these
conditions are met:

1. upstream publishes tagged releases and a documented compatibility policy;
2. `export-spec` has a stable, versioned JSON compatibility contract;
3. licensing is complete enough for the intended distribution model;
4. assertion execution behavior and diagnostics are stable;
5. SQL or DuckDB sources avoid mandatory Parquet round-trips for Graft stores;
6. large dictionaries have a supported composition mechanism;
7. the fixture parity suite identifies every emitted mapping and known loss
   deterministically;
8. binary installation and verification work without requiring package users
   to build Rust code; and
9. adoption reduces Graft's maintained code without weakening its plan,
   commit, provenance, history, or retrieval guarantees.

Until those gates are met, the recommended relationship is integration beside
Graft: data-dict supplies a promising tabular contract and separately invoked
validation surface, while Graft supplies governed acceptance and durable
knowledge history.

## Verification snapshot

On August 6, 2026, both fixtures passed `validate-spec` under upstream commit
`d794c9616f7803199432e9b31b519216aa78d1b0`. The locally built macOS CLI
reported version `0.0.1` and digest
`sha256:7bac8503d995741059758d8b5301700248d3e85f7a03aac2bdc3001c128cb8c8`.
That digest identifies this build artifact only; other platforms and toolchains
must record their own binary digest.
