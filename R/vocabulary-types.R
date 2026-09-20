#' A retained shared vocabulary release
#'
#' `VocabularyRelease` is a typed descriptor for one verified vocabulary
#' publication. Its selection identifies the immutable release in the artifact
#' store; the other properties are materialized from that selection by
#' [graft_read_vocabulary()]. The properties are ordinary R values and do not
#' grant access, approval, or execution authority.
#'
#' @param selection Exact retained [ArtifactSelection].
#' @param vocabulary Retained concepts and relationships.
#' @param bindings Validated bindings to pinned dictionary fields.
#' @param dictionaries Canonical retained dictionary exports keyed by ID.
#' @param references Exact source and export references for the release.
#' @param context Literal context materialized from the release.
#' @export
VocabularyRelease <- S7::new_class(
  "VocabularyRelease",
  package = "graft",
  properties = list(
    selection = ArtifactSelection,
    vocabulary = S7::class_list,
    bindings = S7::class_list,
    dictionaries = S7::class_list,
    references = S7::class_list,
    context = S7::class_character
  )
)
