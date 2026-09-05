# Consumer-facing contract version

graft_contract_version_value <- "0.5.0"

#' Report the Graft consumer contract version
#'
#' `graft_contract_version()` returns the versions a downstream package can
#' pin against instead of hashing Graft's namespace or checking a git commit.
#' The `contract` entry follows semantic versioning for the exported
#' functions, their arguments, and the shapes of the values they return: a
#' change that breaks an existing consumer increments the major component, a
#' compatible addition increments the minor component, and a behavior fix
#' increments the patch component. The remaining entries name the persisted
#' formats a consumer may store, compare, or serialize.
#'
#' @return A named list of character scalars: `contract`, `store_format`,
#'   `plan`, `snapshot_schema`, `manifest`, and `okf`.
#' @export
#' @examples
#' graft_contract_version()$contract
graft_contract_version <- function() {
  list(
    contract = graft_contract_version_value,
    store_format = graft_store_format_version,
    plan = graft_plan_version,
    snapshot_schema = as.character(graft_snapshot_schema_version),
    manifest = graft_manifest_version,
    okf = graft_okf_version
  )
}
