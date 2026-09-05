# Exact reuse and consultation eligibility

Scope: #45 and #46, following #44's application-schema disposition. This is a
bounded implementation contract with executable Graft proofs. It does not
ship Tempest/Rill integration, row-level access control or permanent erasure.

## Decision and smallest shared change

Keep the basis and consultation policy application-owned. Add only
`graft_changes(record_ids = ...)`, filtering identities before result limits.
Both a research evidence selection and a Reader interpretation/preference
selection need it: unrelated store changes can fill a store-wide response before
a later filter sees the selected source or a deleted support. Filtering by ID
also retains tombstones whose returned payload cannot identify a parent.

The filter intersects `class`, uses bound SQL parameters, preserves the existing
window and public result shape, and caps input at 5,000 IDs. `NULL` means all;
`character()` means none. Unknown IDs produce no changes, not evidence of their
existence. The application must inspect `truncated`, materialize its full basis
independently, and cap that basis at 1,000 records including evidence. The
compatible argument addition advances Graft's consumer contract to 0.5.0.

Do not add a general KnowledgeRecord, GraftBasis class, policy DSL, automatic
reference traversal or generic agent runtime. The teaching functions in
`inst/examples/reuse-basis.R` are application recipes, not exported Graft APIs or
a supported serialization format. Their explicit graph describes required
closure; it does not infer every semantic dependency from a dictionary FK.

## Inventory and consumer evidence

- `graft_snapshot()` supplies store identity, store format, exact accepted
  boundary, and schema build identity. `graft_at()` validates the snapshot's
  mapping against a live connection and reconstructs historical reads.
- `graft_history(..., limit = 1)` identifies the exact latest revision at a
  selected boundary. `graft_get(..., include = character())` materializes just
  the selected public record and rejects a deleted current revision.
- `graft_changes()` compares boundary revisions, including deletion tombstones,
  and reports changed records once even over multiple acceptance cycles.
- Tempest's `tempest_knowledge()` accepts an explicit selection of at most 1,000
  Claim, ClaimSupport, EvidenceSpan and Source records. Its daily-briefing guide
  retains prior IDs and deletion tombstones, but filters after a bounded
  store-wide query and can drop required evidence when filling remaining room.
  #50 must replace silent incomplete closure with narrowing or an explicit
  incomplete result that cannot become a successful consultation.
- Tempest main at `4c9753c36ec3704216588d95db38bf2847b03e51` still requires Graft
  consumer contract 0.2.x in its public schema loader. Merged Graft already
  reports 0.4.0; this slice reports 0.5.0. Do not bypass that gate or describe
  generic fixtures as current Tempest runtime compatibility. #50 owns the
  contract update with actual promotion/knowledge/worker evidence.
- Rill ADRs 0002/0003/0004/0007 retain stable Reading Artifact identities,
  immutable Document anchors, Archive/restore, host acceptance and Reader
  boundaries. #51 owns runtime integration; #47/#48 remain access/erasure gates.

The narrative fixture uses an actual Graft store and the shipped data-dict
contract. One graph combines a conclusion and interpretation, their support
records and shared source, plus an independent preference. This tests affected
and unaffected roots together; it is not proof of two application integrations.

## Exact basis and references

A trusted checkpoint records a version, GraftSnapshot, root IDs, one
`record_id/class/revision_id` row per selected record, and explicit directed
outcome/dependency pairs. This pins record/schema/store meaning without storing
a connection, credentials, policy callback or access grant. Resolve in a fresh
process only after opening the intended store and establishing current host
permission. RDS is a trusted-host transport here, not an untrusted import format.

Capture the complete transitive closure declared by the application. Reject
cycles, duplicates, missing records, a selection above 1,000 total records and
partial checkpoints. This bound includes evidence, not just root claims. A
reference to a stable logical ID follows its current revision only when the host
explicitly refreshes the selection. An exact evidence reference resolves the
record revision at the saved boundary; source-version/anchor interpretation
remains an application responsibility. Mixed historical source boundaries need
a separately specified per-reference contract and are outside this recipe.

| Observed condition | Exact historical inspection | New automatic consultation |
|---|---|---|
| Unchanged day | Retain the complete saved selection | Recheck access and eligibility; do not replace it with an empty delta |
| Revised dependency | Preserve the old revision and content | Flag reachable selected outcomes for review; host chooses exclusion or reviewed reuse |
| Missing selected revision / incompatible store or schema | Fail the whole read | Fail; never silently substitute latest or omit a dependency |
| Ordinary deletion | A previously accepted boundary may still resolve | Current closure cannot include the deleted record; retain its ID/tombstone in assessment |
| Archive | Authorized historical inspection remains possible | Exclude according to current app policy; invalidate the affected run |
| Supersession | Retain old and replacement identities | Host excludes the replaced identity and explicitly accepts/selects its successor |
| Permission revoked | Deny even with an old snapshot | Deny, stop affected runs and remove stale context before continuation |
| Permanent Forget | Erased references must fail at every historical boundary | Deny; old checkpoints/backups must never restore erased content |

Only access denial through the teaching host callback is demonstrated for the
last two rows. Graft itself still retains historical bytes; this is not the
permanent purge/backup/restore implementation required by #48. Copies already
returned to a consumer require that consumer's own retention/erasure workflow.

## Changes and dependency review

Assess changes for the saved IDs before the result limit. Keep delete rows even
when their payload is `NULL`; propagate from changed IDs through the saved
reverse dependency graph to selected roots. This is a review signal, not a truth
judgment or an automatic rewrite. The proof changes a source through two
acceptance cycles, flags the interpretation/conclusion but not the unrelated
preference, and keeps old content and evidence exactly reconstructable.

New topical records are a separate, explicitly bounded discovery operation.
`record_ids` does not discover future dependencies or new claims. A host first
checks discovery completeness, applies its relevance/acceptance policy, rebuilds
the full declared closure, and captures a new basis. It never concatenates the
last promotion/change receipt in place of that selection. An unchanged refresh
can advance the accepted boundary while retaining every selected ID/revision.

## Revision, supersession and acceptance

Revise the same ID when correcting the same accepted outcome. A replacement
with a different purpose has its own ID and a host-owned supersession link;
require an existing accepted target, reject self-links and cycles, and retain
both histories. These are host requirements; the recipe tests dependency-cycle
rejection, not an application supersession workflow.
Rill's completed/cancelled follow-up states are not general Graft lifecycle
states. A hypothesis can be accepted without becoming a fact; a preference
remains a preference without a fabricated source.

Two proposals based on one head may conflict. Existing Graft plans reject the
stale second commit after the first succeeds; neither branch silently overwrites
the accepted content. Retrying the exact committed plan is idempotent and adds
no revision. A host must review/replan changed content with a fresh idempotency
key. Authorization can be an explicit direct request or an established host
policy; this contract does not add a human click to every valid acceptance.
Model-generated status/owner fields do not supply that authorization.

## Consultation boundary

The proof registers exactly one no-argument ellmer tool that reads the complete
host-selected basis. It checks current host access and eligibility before and
after materialization, emits nothing on failure, and exposes neither IDs, raw
queries, history, SQL, Commons copies nor a general R executor. The callback is
host code; it is never deserialized from model-produced content. This is the
only exposed read path in the demonstration. Its result is data, not a canonical
Graft tool receipt or an independently verified answer.

Applications exposing additional read paths must enforce the same decision on
all of them, including search, history, calculations, detached Commons sources,
exports, cached resources, and prior chat context. Registering unrestricted
`graft_tools(view)` beside a policy filter defeats that policy. A model-visible
instruction to ignore archived records is not enforcement.

The host serializes consultation with policy changes or checks a policy epoch.
Archive, supersession, dependency review and access changes invalidate affected
active runs and cached consultation resources. Restore permits a newly
authorized run; it does not resume an old epoch. A tool refusal cannot erase
knowledge already in an active chat: cancel or rebuild that context before the
next model request. The teaching tests check refusal in an actual local ellmer
tool loop, correction conflicts and revocation between the pre-read and
post-read checks. Archive/restore, supersession, production revocation and
multi-Reader enforcement remain application work in #47/#50/#51.

## Delivery evidence and remaining owners

`test-changes.R`, `test-reuse-basis.R` and `test-reuse-eligibility.R` exercise this
contract offline. The worker closes and reopens its store in another R process.
A test-only stored tombstone fixture uses the existing revision format because
Graft has no public general record-deletion API; it is neither a new deletion
surface nor a Forget demonstration. `vignettes/reuse-basis.Rmd` is the runnable
handoff to #42. #50/#51 prove app integration; #47/#48 supply the missing access
and erasure enforcement before Rill deployment.
