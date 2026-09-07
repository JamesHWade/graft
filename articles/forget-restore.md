# Design Forget and backup recovery

Permanent Forget must remove private content from accepted history and
its derived copies, while preventing an older backup from bringing it
back. Graft currently has no supported purge or backup/restore API. The
[proposed
design](https://github.com/JamesHWade/graft/blob/main/adr/0006-retire-forgotten-generations-before-restore.md)
and [offline protocol
tests](https://github.com/JamesHWade/graft/blob/main/tests/testthat/test-forget-restore.R)
make that gap explicit for
[\#48](https://github.com/JamesHWade/graft/issues/48). They do not clear
Rill’s production gate.

## Keep the decision outside the backup

Suppose a Reader corrects an accepted interpretation and then chooses
Forget. A backup made after the correction still contains both original
and corrected revisions. Restoring it without consulting the current
Forget decision would make the forgotten interpretation readable again.

The proposal uses a separate host journal to retire the affected
Reader’s store generation before cleanup starts. Access remains blocked
while a replacement is built and verified. Only a replacement image
certified at the current Forget epoch may be served or restored. A stale
database cannot become valid merely by changing its backup’s epoch
field.

| Recovery point | Proposed behavior |
|----|----|
| Before Forget | A verified closed-store backup restores exact accepted corrections, pinned history and receipts. |
| After the decision, before cleanup | Reads and restores remain blocked, including from a fresh worker. |
| During interrupted cleanup | Retry the same approved request; never reactivate the retired store. |
| After replacement publication | Read surviving knowledge from the new store UUID; reject every old snapshot and backup for that Reader. |
| Missing current journal | Refuse recovery until independent freshness evidence is restored. |

## Preview the historical cost

Retiring the whole generation invalidates **all earlier snapshots for
the affected Reader**, including references to retained records. The
proposal requires this to appear in the action preview. Surviving values
and allowed history move to a new store identity; old receipts are not
rewritten and old reuse bases do not silently acquire different
evidence. The second Reader’s store, snapshots and content survive
unchanged.

Dependency scope belongs to the host. In the synthetic fixture,
forgetting one interpretation removes its support link but retains a
source still used by another accepted conclusion. Forgetting the source
removes both dependent outcomes. Real applications must also trace old
links and copied passages. Deleting a Conversation alone must leave
separately accepted Reader Memory and Reading Artifacts intact.

## What the proof establishes

The offline tests use real Graft stores to compare original and
corrected history, rebuild known surviving rows, inspect logical
revision/projection content, and reject old backups through the proposed
host gate. They exercise interruption and retries, exact action
approval, a fresh worker, modified backup metadata, and a read whose
result must be withheld after Forget is accepted.

The journal and replacement builder are test fixtures, not production
APIs. The builder replays known synthetic values and gives them new
acceptance metadata. Local stand-in files represent cache, OKF,
checkpoint and Conversation cleanup; actual product integrations remain
implementation work.

The retained offline backup still contains the original bytes. Restore
denial prevents the application from serving them; it is not physical
erasure. Complete Forget also needs tracked disposal or disclosed
retention of offline backups, external destinations and other derived
copies. The [design inventory and implementation
handoff](https://github.com/JamesHWade/graft/blob/main/adr/0006-retire-forgotten-generations-before-restore.md)
identify those owners and unresolved guarantees.
