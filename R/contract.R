#' Report Graft's artifact and vocabulary contracts
#'
#' Consumer contract 3 removes the native graph store, schema compiler, commit
#' plans, snapshots, and managed working tree. Artifacts and selections retain
#' format 1; the cut does not change their bytes or digest identities.
#' Applications interpret payloads and decide whether evidence is eligible for
#' use. Graft verifies exact retention and records explicit host decisions.
#'
#' @return A named list of character scalars describing the consumer API and
#'   persisted artifact, selection, decision, vocabulary, and binding formats.
#' @export
#' @examples
#' graft_contract_version()
graft_contract_version <- function() {
  list(
    contract = "3.0.0",
    artifact = "1",
    selection = "1",
    decision = "1",
    vocabulary = "graft-vocabulary/1",
    bindings = "graft-bindings/1",
    vocabulary_release = "graft-vocabulary-release/1"
  )
}
