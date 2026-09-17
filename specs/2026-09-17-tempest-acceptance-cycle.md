# Direct Tempest acceptance and withdrawal

Experiment #64, September 17, 2026. This follows the migration and public-input
experiments. The [runner](../tools/experiments/tempest-cycle/run.R) uses the same
[pinned sources](../tools/experiments/pins.json), including Tempest `6d3386c`.

## Question and result

Can a host accept a completed Tempest research proposal directly into artifact
storage, consult it in another process, correct it and withdraw it, without a
native Graft producer or store?

The new fixture exercises that complete path on both metadata drivers. The
manifest path runs acceptance and consumption with Graft absent from its R
library. The Graft path uses the same host decisions and content preservation.
Both retain exact initial, unchanged and corrected acceptance receipts, source
bodies, four evidence records per selection, reports and original promotion
bundle files. The [recorded result](../tools/experiments/tempest-cycle/observed.json)
contains the assertion count and executed failure checks.

The inputs are Tempest's shipped synthetic completed-research proposals, read
through `tempest_read_promotion_bundle()` with independently pinned bundle IDs.
This is new acceptance into an empty artifact store, not a new model-generated
research run. No native receipt, checkpoint export, Graft plan or migration map
participates in the manifest path.

## Host contract

1. **Stage:** validate the proposal with Tempest, preserve both bundle files and
   the report, then save the exact evidence closure as an immutable candidate.
   Saving the candidate grants no consultation eligibility.
2. **Accept:** the host supplies a decision key, review reason, purpose and
   expected preceding decision. Save an immutable acceptance receipt, then append
   the decision to the host journal only after all retained content resolves.
3. **Consult:** require the selected acceptance to be the current eligible host
   decision for the requested purpose. Resolve the exact candidate and its
   dependencies, then call `tempest_artifact_knowledge()`.
4. **Correct:** stage a correction without changing eligibility. A separate host
   acceptance explicitly replaces the preceding decision. An unchanged review
   also has its own receipt while selecting the original evidence revisions.
5. **Withdraw:** append an ineligible decision with the reason and acceptance it
   withdraws. New consultation and host-mediated session resume stop. Historical
   inspection continues to resolve the exact original bytes.

The journal is the host's acceptance boundary. A content revision is not an
acceptance event. Retry with the same decision key returns the recorded event;
changing its inputs fails. Returning that old event never reapproves it after
correction or withdrawal. A deliberate new review would require a new key and
an explicit expected current decision.

The host checks eligibility again before session resume and checks the saved
selection against the currently eligible acceptance. Tempest validates its input
and persists it. Calling Tempest's raw resume function bypasses this host policy;
applications must route consultation through their admission boundary. This
experiment does not revoke an already running chat.

## Preservation and failure checks

Both drivers are checked against the independently read source fixture, not just
against each other. Every evidence row and complete Source resource must match;
the report and two original bundle files must match byte for byte. ProgramArtifact
references and stage/research provenance remain in the retained complete bundle;
there are no executable program payloads in these fixtures.

Tempest's report reference hashes a JSON string. The shipped fixture writes that
string with `writeLines()`, adding one final LF. The host verifies the product
reference after removing that single framing LF, while preserving the original
file bytes with their separate artifact digest. This is the shipped fixture's
serialization convention, not a general report import API.

Negative tests cover missing approval, wrong purpose, stale expected decisions,
wrong bundle pins, changed reports, corrupted retained bytes, mismatched saved
sessions and retries that change a decision. An injected failure of the final
journal publication leaves no acceptance; retry reuses the saved receipt and
publishes one decision. This tests a handled publication failure, not power-loss
recovery or a distributed transaction.

## Architecture decision

**Recommend retiring Graft's current graph/compiler architecture from the proposed
artifact composition.** The tested workflow now has a complete route through
Tempest's public output and input contracts without Graft at either end. Together
with vocabulary, Commons roundtrip and historical migration evidence, this
removes the demonstrated consumer requirement for its native ledger.

Keep the responsibilities: exact bytes and dependencies, immutable candidates and
acceptance receipts, and host-owned current eligibility. Commons still owns
analytical execution; data-dict owns local contracts; the vocabulary publisher
owns shared terms and bindings. Persistent artifacts compose those components.
A general ontology engine or second compiler is not needed by this workflow.

This is a recommendation to replace the current package's role, not a claim that
this experiment directory is a shipped replacement. No existing API is removed
in this PR. The next implementation is to place the artifact boundary in its
intended host/module, implement #49's required publication/recovery contract, and
remove obsolete integrations directly. Backwards compatibility is not a gate.

### Total machinery and limits

The new host includes proposal translation, report verification, immutable
candidate/receipt construction, the acceptance journal, admission, withdrawal
and session exercise. It also requires the existing shared content module and
metadata driver module. The runner, fixture orchestration, regression tests and
Tempest's public artifact input are additional; none are hidden as free adapters.
Line counts are recorded in the result receipt and are not performance measures.

The comparison deliberately keeps host policy identical for both drivers. Graft
could store that policy in native transactions; this experiment does not compare
such an optimized design or establish a universal storage-performance advantage.
Its result is that the native graph, compiler and store are unnecessary for the
bounded workflow. Both choices still need a content owner and application policy.

The fixture has one research topic, one trusted writer, bounded local files and
explicit ordered decisions. It retains history rather than implementing Forget.
Concurrency, power loss, authenticated actors, Reader isolation, backup admission,
active-task cancellation and production recovery remain outside its claim.
Issues #47/#48/#49 cover those requirements. They must be met before production;
they do not create a backwards-compatibility obligation for a pre-production API.
