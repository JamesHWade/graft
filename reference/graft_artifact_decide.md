# Record host decisions about exact artifact selections

Retain acceptance and withdrawal decisions in a bounded, append-only
journal. Applications make the decisions and enforce access policy;
Graft records them and checks the mechanical conditions for current
consultation.

## Usage

``` r
graft_artifact_decide(
  store,
  stream,
  key,
  expected,
  selection,
  action,
  actor,
  reason,
  purpose,
  max_decisions = 1000L,
  max_metadata_bytes = 1024^2,
  max_artifacts = 1000L,
  max_selection_bytes = 1024^2
)

graft_artifact_read_decision(
  store,
  stream,
  decision = NULL,
  max_decisions = 1000L,
  max_metadata_bytes = 1024^2
)

graft_artifact_reuse(
  store,
  stream,
  decision,
  purpose,
  eligible,
  max_decisions = 1000L,
  max_metadata_bytes = 1024^2,
  max_artifacts = 1000L,
  max_selection_bytes = 1024^2
)
```

## Arguments

- store:

  A handle returned by
  [`graft_artifact_store()`](https://jameshwade.github.io/graft/reference/graft_artifact_store.md).

- stream:

  Host-chosen identity for one independently reviewed subject.

- key:

  Host-chosen idempotency key, unique within the stream. A new review
  requires a new key, even when the selection is unchanged.

- expected:

  Exact predecessor decision digest, or explicit `NULL` for an empty
  stream. It is never inferred from current state.

- selection:

  Exact digest returned by
  [`graft_artifact_select()`](https://jameshwade.github.io/graft/reference/graft_artifact_select.md).

- action:

  Explicit host decision: `"accept"` or `"withdraw"`.

- actor:

  Host-supplied actor identity. This is a claim, not authentication.

- reason:

  Host-supplied review or withdrawal reason.

- purpose:

  One explicit consultation purpose. Withdrawal must retain the purpose
  of the acceptance it withdraws.

- max_decisions:

  Maximum number of committed records in the stream.

- max_metadata_bytes:

  Maximum aggregate encoded journal bytes to read or publish. Staging
  files are not committed records and are excluded.

- max_artifacts:

  Maximum number of distinct artifacts in the selection.

- max_selection_bytes:

  Maximum encoded selection metadata bytes.

- decision:

  Exact decision digest, or `NULL` to inspect the current head.

- eligible:

  Explicit current host consultation decision, a single logical value.
  `graft_artifact_reuse()` requires `TRUE`; it does not derive policy.

## Value

Recording and inspection return a list with `id`, `sequence`, `stream`,
`key`, `previous`, `action`, `selection`, `actor`, `reason` and
`purpose`. Inspection of an empty stream with `decision = NULL` returns
`NULL`. Reuse returns `decision` and `selection`, the latter having the
shape returned by
[`graft_artifact_read_selection()`](https://jameshwade.github.io/graft/reference/graft_artifact_select.md).
No return value asserts factual truth.

## Details

Stream, key, actor, reason and purpose are nonempty, unpadded strings of
at most 1024 UTF-8 bytes without control characters. R attributes are
discarded. Each acceptance verifies the complete exact selection before
publication. A withdrawal must name the current acceptance's selection
and purpose. It remains possible when payloads are missing or corrupt.

Committed keys bind all normalized request fields, including `expected`.
Repeating an identical committed request returns its original historical
record, even after correction or withdrawal. It never advances the head
or restores eligibility. Changed retries fail. An uncommitted
interrupted request has no recorded decision; retries must still satisfy
the predecessor guard.

Inspection verifies the journal and returns decision metadata, without
resolving payloads or granting consultation. Current reuse requires
explicit host eligibility, the current accepted decision, an exact
purpose match and successful verification of every selected payload. It
returns the decision and verified selection; callers resolve individual
bytes with
[`graft_artifact_read()`](https://jameshwade.github.io/graft/reference/graft_artifact_store.md).
This is a point-in-time check, not a lasting permit. Applications must
enforce access on every path, including low-level artifact reads and
historical inspection.

A complete immutable numbered record is the commit point. Reopening
derives the head from contiguous, digest-verified records. Interrupted
staging is ignored and never promoted automatically; a lost response
after publication is recoverable by an identical retry. History scanning
is bounded by count and total encoded bytes, and the same or larger
limits are needed on reopen. This supports trusted local files and one
writer. Predecessor checks reject stale sequential decisions; they do
not provide concurrent compare-and-swap, authentication, power-loss
durability, backup recovery or permanent erasure.

## Examples

``` r
path <- tempfile("decisions-")
store <- graft_artifact_store(path, create = TRUE)
ref <- graft_artifact_save(store, "report", charToRaw("Evidence"), "text/plain")
selection <- graft_artifact_select(store, list(ref))
accepted <- graft_artifact_decide(
  store, "research:topic", "review-1", expected = NULL,
  selection = selection, action = "accept", actor = "reviewer",
  reason = "Evidence reviewed", purpose = "research"
)
graft_artifact_reuse(
  store, "research:topic", accepted$id, "research", eligible = TRUE
)$selection$artifacts
#> [[1]]
#> [[1]]$id
#> [1] "report"
#> 
#> [[1]]$revision
#> [1] "3a84f3ebf6d2afced58a6b09db658a2641d2acfb462399ee913d947da375c605"
#> 
#> 
graft_artifact_decide(
  store, "research:topic", "withdraw-1", expected = accepted$id,
  selection = selection, action = "withdraw", actor = "reviewer",
  reason = "Evidence needs correction", purpose = "research"
)
#> $id
#> [1] "5b91b312c14e3d5210a94a735d3349ea8e7be559472c9f62c10ee3701ce81cd4"
#> 
#> $sequence
#> [1] 2
#> 
#> $stream
#> [1] "research:topic"
#> 
#> $key
#> [1] "withdraw-1"
#> 
#> $previous
#> [1] "6603b2017cf558be813ea42c1357dcc446daf719f194e1c31f8ad95cfee5384a"
#> 
#> $action
#> [1] "withdraw"
#> 
#> $selection
#> [1] "cd53f49cf442357fd397729b92893e47271adbf8ff492d7957d3f968b198b05e"
#> 
#> $actor
#> [1] "reviewer"
#> 
#> $reason
#> [1] "Evidence needs correction"
#> 
#> $purpose
#> [1] "research"
#> 
graft_artifact_read_decision(store, "research:topic", accepted$id)
#> $id
#> [1] "6603b2017cf558be813ea42c1357dcc446daf719f194e1c31f8ad95cfee5384a"
#> 
#> $sequence
#> [1] 1
#> 
#> $stream
#> [1] "research:topic"
#> 
#> $key
#> [1] "review-1"
#> 
#> $previous
#> NULL
#> 
#> $action
#> [1] "accept"
#> 
#> $selection
#> [1] "cd53f49cf442357fd397729b92893e47271adbf8ff492d7957d3f968b198b05e"
#> 
#> $actor
#> [1] "reviewer"
#> 
#> $reason
#> [1] "Evidence reviewed"
#> 
#> $purpose
#> [1] "research"
#> 
unlink(path, recursive = TRUE)
```
