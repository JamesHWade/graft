# Completed output handoff conformance

Source-only prototype for [Graft #66](https://github.com/JamesHWade/graft/issues/66).
Read the [proposal](../../specs/2026-10-10-output-handoff-design.md) for ownership,
the public producer inventory, and upstream requests. These functions are proposed
host fixture interfaces, not Graft package exports.

The handoff module validates complete owned bytes or exact retained references,
preserves producer evidence and exact host inputs, and returns a draft candidate.
The Commons and deputy adapters supply explicitly mapped native content. Review
and fresh eligibility remain host responsibilities.

## Run the fixture

Run from the Graft repository root with R 4.3 or later and the package's test
dependencies. The full fixture additionally needs the dependencies of the pinned
Commons and deputy packages, including `ellmer`, `DBI`, `duckdb`, `httpuv`,
`promises`, and `callr`. It uses child R processes and localhost sockets, with no
model API key or external model request.

```sh
# One-time source download; verifies immutable archive digests.
Rscript tools/output-handoff/prepare.R /tmp/graft-handoff-sources

# Offline tests: sources are extracted anew from verified archives.
Rscript tools/output-handoff/run.R --sources /tmp/graft-handoff-sources

# Envelope/storage tests alone; no upstream archives or HTTP server.
Rscript tools/output-handoff/run.R --core-only
```

`prepare.R` is the only network step. `run.R` does not install packages or replace
the user's libraries. Source commits and archive digests are in `pins.json`.
An archive mismatch fails before source loading. To update a pin, deliberately
replace its commit, URL, and digest together, inspect the upstream contract, and
rerun the full fixture. Do not silently fall back to installed producer versions.

The dedicated `.github/workflows/output-handoff.yaml` job runs this full fixture
for relevant pull requests and main changes, with immutable producer and ellmer
pins in its isolated CI library. It can also be dispatched manually.

The observed ellmer version is recorded in the pins. The runner reports its
actual installed version; a different version needs fresh conformance evidence.
The Commons `trusted()` route comes from draft PR #414 and is provisional.

## What the tests establish

- Report, explicit table JSON, and valid inline PNG survive the Commons direct
  measure route and the deputy designated-tool route with byte verification.
- A real deputy Agent preserves the original `ContentToolResult` before model
  narration, including when its final prose deliberately contradicts the tool.
- A promise-returning producer completes asynchronously; failed, denied, missing,
  or delivery-failed producer results cannot become successful handoffs.
- A worker's owned PNG bytes remain available after its temporary file and process
  are gone. A path or digest alone cannot stand in for retained content.
- Malformed, partial, oversized, or corrupt packets fail, exact retries reuse
  references, and corrected content produces an inspectable new revision.
- Preservation remains a draft until explicit acceptance. A fresh R process
  recalls all exact bytes without Commons or deputy loaded. Withdrawal returns no
  current content while historical exact reads remain available.
- Host eligibility is checked before writing and again before root publication.

The local SSE transport is a test adapter. Its tool requests and JSON response
protocol are not a host wrapper or Graft production agent interface. The fixture
uses public constructors and results, not Commons private tool constructors,
private `gt` fields, deputy test helpers, or arbitrary R-object persistence.

## Module layout

| File | Responsibility |
| --- | --- |
| `handoff.R` | Bounded neutral packet validation and draft candidate retention |
| `producers.R` | Commons native-content and deputy completed-result adapters |
| `tests/helper-producers.R` | Synthetic public producer, worker, and local HTTP adapter |
| `tests/test-handoff.R` | Envelope integrity, bounds, dependencies, retries, draft policy |
| `tests/test-producers.R` | Actual public producer routes and runtime failures |
| `tests/test-lifecycle.R` | Exact input closure, fresh-session recall, withdrawal |
| `pins.json`, `prepare.R`, `run.R` | Immutable source preparation and standalone runner |

## Limits

The test measure authors a structured table and its evidence strings explicitly.
This does not establish a public lossless export for Commons' rendered data frames
or `gt` tables. Its authored Commons label is retained as producer metadata; it
does not prove Commons chat classification or scientific truth. Retaining exact
host-selected inputs also does not prove the producer actually used them.

The core defaults to 128 outputs, 1 MiB per output, 4 MiB aggregate output, and
64 KiB metadata, subject to the Graft store bounds. It validates opaque bytes and declared media
types, not a table's scientific meaning or an image decoder's safety. Generation,
preservation, and host acceptance are separate steps. Saving code-like content
does not execute it or register a tool.

Local multi-artifact publication is not transactional. A failed handoff can leave
unreferenced drafts, but it returns no successful root. Hosts must authorize
retries and recheck current policy; a retained event alone does not prove delivery.
This fixture does not implement application authorization, permanent Forget,
production restore admission, or a general worker runtime.

Deputy's strict `TrustedResults` policy permits the designated local producer
and Graft's read-only memory tool together. It prohibits unrestricted model code,
MCP/provider tools, delegation, and unsafe/unannotated tools alongside that
producer. The separate Commons direct measure route does not bypass that policy.
