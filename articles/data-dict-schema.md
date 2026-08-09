# Use a data-dict contract with graft

[`data-dict.yaml`](https://data-dict.tidyverse.org/) describes related
tables, their columns, constraints, relationships, and domain vocabulary
for people and agents. graft can use a resolved data-dict as an
alternative, table-first contract provider. data-dict never becomes the
ledger or an acceptance path.

The responsibilities remain separate:

- data-dict describes the source tabular contract and offers separate
  upstream validation commands;
- graft compiles the supported subset into the same canonical runtime
  contract used for LinkML;
- graft turns candidates into a read-only plan, accepts one checked plan
  in a transaction, and retains immutable revisions; and
- `.graft.json` is the self-contained contract snapshot stored with
  history.

## Use the Graft table profile

The first adapter profile is deliberately strict. A contract must
satisfy all of these rules:

- the document has one non-empty top-level `name`;
- every YAML column declares a `type`, because `export-spec` omits
  untyped columns;
- table and column names produce non-empty, case-insensitively unique
  Graft projection names and unambiguous `table.column` contract keys,
  and table projections do not use the reserved `_graft_` prefix;
- every table has exactly one scalar `string` primary key named `id`;
- primary IDs are public, non-empty after trimming, and globally unique
  across all tables in a Graft store, and a primary `id` cannot also be
  a foreign key; and
- foreign keys are scalar strings that target a concrete table’s primary
  `id`, and the resolved `foreign_key` constraint and `references`
  metadata must both be present.

Supported non-key columns are scalar types or one-level lists of scalar
types. Structs, nested lists, and list-valued foreign keys are rejected
rather than flattened or guessed. Scalar `number(id)` and
`list(number(id))` columns are also rejected because numeric codes
cannot be lowered into exact text without changing equality. Write
identity-like codes as quoted `string` values instead. These are
`graft-table-v1` restrictions, not general data-dict restrictions.

For example:

``` yaml
$version: 0.1.0
$learn_more: https://data-dict.tidyverse.org/
name: personinfo
version:
  number: 0.1.0

tables:
  - name: organization
    description: Each row is one organization.
    columns:
      - name: id
        type: string
        constraints: [primary_key]
        examples: ["org:daily-planet", "org:justice-league"]
      - name: name
        type: string
        constraints: [required]
        examples: ["Daily Planet", "Justice League"]

  - name: person
    description: Each row is one person.
    columns:
      - name: id
        type: string
        constraints: [primary_key]
        examples: ["person:clark-kent", "person:lois-lane"]
      - name: full_name
        type: string
        constraints: [required]
        examples: ["Clark Kent", "Lois Lane"]
      - name: organization_id
        type: string
        constraints: [foreign_key]
        examples: ["org:daily-planet", "org:justice-league"]
      - name: private_notes
        type: string
        display: restricted
        examples: ["Synthetic restricted example"]

relationships:
  - join: person.organization_id = organization.id
    cardinality: many-to-one
```

The `$version` in this YAML is the **source-spec version** understood by
the YAML toolchain. `export-spec` emits a different top-level
`$version`: the **export-format version** for the resolved JSON
compatibility boundary. Both happen to be `0.1.0` at the pinned upstream
commit, but graft records them separately as `source_spec_version` and
`export_format_version` rather than assuming that they will remain
equal.

The adapter maps tables to Graft classes, columns to slots, enum values
to local enum contracts, one-level lists to value relations, and
`display: restricted` to Graft’s sensitive-field policy. Scalar foreign
keys become reference-validation slots: planning checks their target
IDs, but they do not become graph traversal edges.

## Compile YAML with an explicit CLI

YAML compilation runs only data-dict’s `export-spec` command rather than
reimplementing its evolving YAML rules in R. It does not run
`validate-meta` or `validate-data`; run those separately when you want
upstream validation. Install and pin the CLI yourself. graft never
downloads or builds it during package use.

graft reads the source bytes once and creates a private snapshot before
doing any YAML work. YAML expression evaluation is explicitly disabled,
regardless of the caller’s ambient `yaml.eval.expr` option. The
typed-column preflight, source-spec version read, `export-spec`
subprocess, and source-byte content digest all use that same snapshot. A
concurrent edit to the original path therefore cannot make preflight,
resolved output, and the source/build fingerprints describe different
inputs.

``` bash
cargo install \
  --git https://github.com/tidyverse/data-dict \
  --rev d794c9616f7803199432e9b31b519216aa78d1b0 \
  data-dict-cli
```

Let graft find `data-dict` on `PATH`, or select an executable
explicitly. For a YAML source, graft hashes the selected executable
before `export-spec`, checks the same digest immediately afterward, runs
`--version`, and checks the digest again. If the executable changes
during either command, compilation fails rather than combining output
and provenance from different binaries. The observed CLI version and
SHA-256 digest are recorded. The optional revision is copied from the
`graft.data_dict_revision` option shown below or the
`GRAFT_DATA_DICT_REVISION` environment variable; it is caller-supplied
provenance, not a commit verified from the binary.

``` r

library(graft)

options(
  graft.data_dict_cli = "/path/to/data-dict",
  graft.data_dict_revision =
    "d794c9616f7803199432e9b31b519216aa78d1b0"
)

schema <- graft_schema(
  "data-dict.yaml",
  output = "personinfo.graft.json"
)
```

The compiled manifest records the YAML source-spec version, resolved
JSON export-format version, observed CLI version and executable digest,
optional caller-supplied revision, adapter version, a sanitized public
dictionary, and the mapping report. Provider metadata omits graft’s
configured executable path, original input-file path, and private
snapshot path. Retained public contract text is not scanned for
arbitrary path-like strings.

## Compile resolved JSON without the CLI

CI or a schema-authoring environment can resolve the dictionary once:

``` bash
data-dict export-spec data-dict.yaml > personinfo.data-dict.json
```

Treat that JSON as trusted build input. Its top-level `$version` is the
resolved export-format version, not proof of the YAML source-spec
version. graft checks the supported export version and adapter shape,
but it cannot prove that a JSON file really came from `export-spec`. It
rejects `export-data` row payloads and column profiles, including nested
profiles, so those export-data-derived observations cannot enter the
contract automatically. Duplicate object keys are also rejected rather
than resolved by parser order. Version objects, column constraints, and
enum values must retain their resolved scalar or flat-array shapes;
nested containers are rejected rather than recursively flattened into
contract semantics. Dataset version numbers must retain three
dot-separated numeric components with valid optional suffixes, dates
must be valid `YYYY-MM-DD` values, and hashes remain opaque strings. The
manifest schema ID, name, and version are derived deterministically from
the dataset name and version, while its source-file digest binds the
exact captured input bytes. This is not a general sensitive-data
scrubber: retained public metadata can still contain observed or
sensitive values that an author embedded manually. graft also checks
JSON number tokens before lossy numeric conversion. It fails closed on
every token whose magnitude exceeds `2^53 - 1` and on any lexically
nonzero token that would overflow to a non-finite R value or underflow
to zero. Exact identifiers and codes must be quoted strings. The same
lexical guard applies to resolved JSON emitted by the CLI for a YAML
source.

Anyone with graft can then compile trusted resolved JSON using R alone:

``` r

schema <- graft_schema(
  "personinfo.data-dict.json",
  output = "personinfo.graft.json"
)
```

Resolved JSON has no observed CLI version or executable digest. If an
optional revision is configured, it remains caller-supplied rather than
verified CLI provenance. Commit the source dictionary, resolved export,
generation record, and compiled `.graft.json` together when reviewable
and reproducible schema generation matters.

Provider metadata is allowlisted. Unknown or duplicate fields fail
compilation instead of disappearing, and optional CLI fields must agree
with whether the source was YAML or resolved JSON. The private input
`source_path` is the only accepted provider field that is deliberately
removed from the public manifest.

## Inspect the boundary

The usual typed S7 properties remain unchanged:

``` r

schema@name
schema@version
schema@structural_digest
names(schema@classes)

person <- schema@classes$person
person@label_slot
person@search_slots
person@slots$organization_id@object_reference
person@slots$private_notes@sensitive
```

The nonstructural dictionary section records known defaults and
limitations:

``` r

schema@manifest$dictionary$profile
schema@manifest$dictionary$requirements
schema@manifest$dictionary$mapped
schema@manifest$dictionary$not_enforced
```

The compiled manifest is public contract metadata. Names, descriptions,
details, glossary entries, enum values, units, assertions,
relationships, joins, and sensitivity declarations remain visible in
`schema@manifest$dictionary$document`; do not place secrets in those
fields. `display: restricted` protects accepted record payloads during
retrieval, not the schema description itself. The adapter cannot
identify observed or sensitive values manually embedded in retained
descriptions, details, glossary terms, enum values, units, assertions,
or relationship metadata.

Before publication, graft removes every column’s `examples` and `range`,
the dataset `origin`, every table `origin`, and every table `source`
locator. It does not preserve the full resolved document. The raw input
still affects the source and build digests, so changing a redacted value
remains detectable. Those digests do not reveal the value in cleartext,
but they do permit equality tests and offline guessing of low-entropy
values; redaction is not a secrecy boundary. The mapping is
intentionally narrower:

- representative examples and ranges are redacted and never become Graft
  acceptance bounds;
- assertion text is public metadata but is never executed by Graft;
- non-primary uniqueness, relationship cardinality, join aliases,
  conflicts, range joins, and multi-column join pairs are not enforced;
- `export-data`-derived rows and profiles are rejected, while dataset
  and table origins and table source locators are redacted without being
  read or validated;
- for `datetime` and `list(datetime)`, an omitted `time_zone` requires
  every character value to use RFC 3339 `Z` or `±HH:MM`;
  `time_zone: UTC` instead requires a zoneless value and interprets it
  as UTC;
- both supported character forms require `T`, seconds, and no more than
  six fractional digits. `POSIXt` values are accepted as resolved
  instants, while `Date` values are rejected for these data-dict
  datetime contracts;
- `time_zone: naive` and named zones such as `America/Detroit` are
  rejected at compilation; scalar and list `number(id)` columns are also
  rejected in favor of quoted string codes;
- number measures and units remain public metadata, while supported
  numeric values use Graft’s double representation; and
- candidate values use Graft’s R-facing coercion rules, not data-dict’s
  Parquet-metadata validation rules.

Missing-value semantics also differ. Graft treats required empty or
whitespace-only scalar strings and empty required lists as missing,
rejects missing elements inside collections, and does not treat a list
as present merely because its container is non-null. Empty or
whitespace-only enum strings are rejected. Optional scalar foreign keys
normalize empty and whitespace-only strings to missing before reference
validation. These checks are stricter than data-dict’s container
nullness rules.

The report is a review aid, not an exhaustive semantic equivalence
proof. Raw provider changes, including redacted examples, ranges,
origins, and source locators, alter source and build digests. Only
changes to the mapped acceptance contract alter the structural digest.

## Plan and accept normally

The contract provider does not create a second write path. Candidate
list names match data-dict table names, and all mutation still passes
through the same plan and commit boundary:

``` r

store <- graft_open(schema, ":memory:", okf = "disabled")

records <- list(
  organization = data.frame(
    id = "org:daily-planet",
    name = "Daily Planet"
  ),
  person = data.frame(
    id = "person:clark-kent",
    full_name = "Clark Kent",
    organization_id = "org:daily-planet",
    private_notes = "Do not display"
  )
)

plan <- graft_plan(
  store,
  records,
  graft_provenance(
    producer = "data-dict-example",
    idempotency_key = "personinfo-v1"
  )
)

if (plan@valid) {
  graft_commit(store, plan)
}
```

[`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md)
and
[`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md)
apply Graft’s existing sensitive-field filtering, so `private_notes` is
accepted into the authoritative revision but omitted from default
retrieval. Primary IDs remain public operational keys and cannot use
`display: restricted`.

## Know when LinkML remains the better source

Use LinkML when the contract needs inheritance, class or predicate URIs,
polymorphic references, Graft record roles, narrative or semantic
statement shapes, custom identity policies, origin keys, qualifier
slots, explicit search weights, or graph traversal relationships.
data-dict does not currently express those concepts, and the adapter
does not invent them silently. Its mapping report lists known defaults
and unrepresented semantics, but it is not exhaustive.

Struct columns and nested lists are also rejected by `graft-table-v1`
rather than flattened lossily. These are adapter limits, not limitations
of the upstream data-dict specification.
