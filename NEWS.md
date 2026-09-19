# graft 0.0.0.9000

* Graft now contains persistent artifacts, exact dependency selections, host decision history, and shared vocabulary. Native graph stores, LinkML compilation, commit plans, snapshots, calculations, managed OKF trees, and graph agent adapters are removed without compatibility wrappers. The website describes the supported artifact architecture (#74).
* `graft_artifact_decide()`, `graft_artifact_read_decision()`, and `graft_artifact_reuse()` retain explicit host acceptance and withdrawal, guard predecessors and identical retries, and separate historical inspection from current purpose-bound consultation (#73).
* `graft_artifact_select()` and `graft_artifact_read_selection()` retain and verify bounded exact dependency closures (#72).
* `graft_artifact_store()`, `graft_artifact_save()`, and `graft_artifact_read()` retain bounded opaque bytes as immutable revisions with verified exact reads (#71).
* `graft_contract_version()` reports consumer contract 3.0.0 and the retained artifact, selection, decision, vocabulary, binding, and vocabulary-release formats. Existing artifact identities are unchanged (#74).
* `graft_vocabulary_publish()` and `graft_vocabulary_read()` retain shared concepts, relationships, exact data-dict bindings, source bytes, and literal context across dictionary corrections (#76).
