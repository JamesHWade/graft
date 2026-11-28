#' A retained shared vocabulary release
#'
#' A `VocabularyRelease` describes one verified vocabulary publication. Its
#' selection identifies the immutable release in the artifact store.
#' [graft_read_vocabulary()] reads the other properties from that selection.
#' These properties are ordinary R values; they do not grant access, approval,
#' or execution authority.
#'
#' @param selection Exact retained [ArtifactSelection] for this release.
#' @param vocabulary Retained concepts and relationships.
#' @param bindings Validated bindings to pinned dictionary fields.
#' @param dictionaries Canonical retained dictionary exports keyed by ID.
#' @param references Exact source and export references for the release.
#' @param context Literal context stored with the release.
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

S7::method(print, VocabularyRelease) <- function(x, ...) {
  release <- x@bindings$release
  label <- if (
    is.character(release) && length(release) == 1L && !is.na(release)
  ) {
    release
  } else {
    x@selection@id
  }
  cat(
    "<VocabularyRelease ",
    label,
    " selection=",
    x@selection@id,
    " dictionaries=",
    length(x@dictionaries),
    ">\n",
    sep = ""
  )
  invisible(x)
}
