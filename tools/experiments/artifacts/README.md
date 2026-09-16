# Persistent artifact experiment (#59)

This is disposable research code, not a supported storage API. Run from the
repository root after running [`setup.R`](../README.md#run) and setting
`GRAFT_EXPERIMENT_HOME` to its attested environment directory:

```sh
Rscript tools/experiments/artifacts/run.R
```

The same conformance tests run against two compositions:

- **Manifest:** immutable content and JSON metadata files, a replaced
  current-revision map, and explicit host selection/policy files.
- **Graft:** the same content and selection/policy files, with public Graft
  plan/commit, find and history APIs replacing metadata files/current map.

`content.R` is shared host/storage glue. `backends.R` contains both metadata
adapters. `fixture.R` produces actual Markdown, Parquet and PNG bytes. No model
or network connection is used. The manifest path never loads Graft. Graft's
schema validates the envelope; the experiment validates the JSON manifest and
its dependency closure. This intentionally exposes how much artifact behavior
still lives outside either Commons or Graft.

The producer, unchanged consumer and correction consumer are separate terminated
R processes. Checkpoints contain only JSON identities/digests. Old selected bytes
are recovered after source/dependency revisions; changing or deleting the
producer's mutable file does not alter the stored content. A draft can be saved
without approval. Historical inspection and current consultation have separate
paths; host withdrawal denies consultation without pretending to erase history.
Each selection has its own policy record; approval or withdrawal of another
selection, including one with a different purpose, does not alter its eligibility.

## Limits that matter to the decision

- Trusted, synthetic, local, single-writer stores only. Replacement stages the
  old file as a backup before renaming the new file into place, including on
  Windows. A failed install restores the old file or reports its retained backup
  path if restoration also fails. This is not atomic for concurrent readers and
  does not prove power-loss durability, cross-store transactions or secure erasure.
- Metadata is published after bytes. Interrupted publication can leave orphan
  bytes; retry recovers without duplication. The experiment retains orphans;
  safe retention/collection and interrupted metadata-index publication need a
  production protocol under #49. It never reports success for missing bytes.
- Files are bounded to 1 MiB, selections/current lists to 50 entries, Graft
  history lookup to 100 revisions. An unavailable bounded historical revision
  fails explicitly. There is no pagination or arbitrary warehouse scale claim.
- A revision is the digest of this fixture's serialized metadata, not a universal
  canonical-JSON standard or Graft acceptance event ID. Graft also preserves its
  native revision/commit evidence. Migrating real consumers must preserve or map
  those distinct identities explicitly.
- The meaning fixture is a small retained synthetic release. #60 supplies real
  binding validation; #61 tests data-dict execution; #62 composes those results.
- Approval here is an explicit synthetic host action. File contents are not an
  authentication boundary. Cached chat copies require host invalidation after
  withdrawal. #47 and #48 remain production access and Forget/restore gates.
- Text previews are truncated, tables return two rows, images return a verified
  content descriptor for an explicit renderer. No RDS or stored-code execution.

No public Graft functions, package dependencies or existing stores are changed.
