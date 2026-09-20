#' Report Graft's artifact and vocabulary contracts
#'
#' Consumer contract 3.2 adds closed artifact backup bundles with externally
#' supplied identity receipts and strict restore verification. Contract 3.1 adds
#' bounded manifests and replacement plans. These operations do not authorize
#' Forget or backup restore.
#' Consumer contract 3 removes the native graph store, schema compiler, commit
#' plans, snapshots, and managed working tree. Artifacts and selections retain
#' format 1; the cut does not change their bytes or digest identities.
#' Applications interpret payloads and decide whether evidence is eligible for
#' use. Graft verifies exact retention and records explicit host decisions.
#'
#' @return A named list of character scalars describing the consumer API and
#'   artifact, manifest, replacement, backup, selection, decision, vocabulary, and
#'   binding formats.
#' @export
#' @examples
#' graft_contract_version()
graft_contract_version <- function() {
  list(
    contract = "3.2.0",
    artifact = "1",
    manifest = "graft-artifact-manifest/1",
    replacement = "graft-artifact-replacement/1",
    backup = "graft-artifact-backup/1",
    selection = "1",
    decision = "1",
    vocabulary = "graft-vocabulary/1",
    bindings = "graft-bindings/1",
    vocabulary_release = "graft-vocabulary-release/1"
  )
}
