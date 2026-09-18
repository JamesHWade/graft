#' Publish and read a shared vocabulary release
#'
#' Validate explicit concepts, directed relationships and qualified dictionary
#' bindings, then retain their exact source bytes and resolved dictionary exports
#' in one artifact selection. Publication grants no approval or execution
#' authority. Reading a historical release does not re-run data-dict.
#'
#' @param store A [graft_artifact_store()] handle.
#' @param path Path to a `graft-bindings/1` JSON companion file. Referenced
#'   vocabulary JSON and dictionary YAML files must be siblings pinned by SHA-256.
#'   Each input file is limited to 1 MiB, with at most 498 dictionaries per
#'   release. Sources and generated outputs must fit the store's aggregate byte
#'   limit. Dictionaries must be self-contained;
#'   validation/export runs against captured source bytes in a temporary file.
#' @param selection Exact selection digest returned by
#'   `graft_vocabulary_publish()`.
#'
#' @details
#' The companion format records its release, vocabulary release, dictionary
#' identities, workflows, source digests, bindings and qualified assertions.
#' Concepts map to one qualified dictionary/table/field. Relationships require
#' explicit domain and range concepts and matching endpoint bindings, including
#' scope, grain and condition. Assertions retain their source, status, negation,
#' time and scope; publication does not verify that an assertion is true.
#'
#' Matching concepts do not prove joins, comparable units, permissions or program
#' authority. No expression evaluation, ontology inference or code loading occurs.
#' See the shared vocabulary article for the complete companion format.
#'
#' Publishing requires the optional `datadict` package and an installed data-dict
#' binary. Only its public `validate-spec` and `export-spec` commands are used.
#' Graft preserves their resolved JSON and validation provenance; data-dict owns
#' the local table contract. Historical reads require only Graft.
#'
#' @returns `graft_vocabulary_publish()` returns an immutable selection digest.
#'   `graft_vocabulary_read()` returns `vocabulary`, `bindings`, `dictionaries`,
#'   `references`, and `context` (Markdown generated from the same release).
#' @export
graft_vocabulary_publish <- function(store, path) {
  artifact_check_store(store)
  source <- vocabulary_source_bytes(path)
  b <- vocabulary_json(source)
  vocabulary_companion(b)
  files <- file.info(file.path(
    dirname(path),
    c(
      b$vocabulary$path,
      vapply(b$dictionaries, \(ref) ref$path, character(1))
    )
  ))
  sizes <- files$size
  sizes[files$isdir %in% TRUE] <- NA_real_
  vocabulary_check_source_budget(c(length(source), sizes), store$max_bytes)
  vocabulary_bytes <- vocabulary_check_pinned_file(dirname(path), b$vocabulary)
  dictionary_bytes <- lapply(b$dictionaries, \(ref) {
    vocabulary_check_pinned_file(dirname(path), ref)
  })
  vocabulary_check_source_budget(
    c(length(source), length(vocabulary_bytes), lengths(dictionary_bytes)),
    store$max_bytes
  )
  ids <- vapply(
    b$dictionaries,
    function(ref) {
      vocabulary_check_text(ref$id, "dictionary id")
      ref$id
    },
    character(1)
  )
  if (anyDuplicated(ids)) {
    vocabulary_binding_error("Duplicate dictionary ID")
  }
  dictionaries <- stats::setNames(
    lapply(dictionary_bytes, vocabulary_read_dictionary),
    ids
  )
  v <- vocabulary_json(vocabulary_bytes)
  vocabulary_validate(b, v, dictionaries)
  refs <- list()
  records <- list()
  prepare <- function(id, bytes, media_type, dependencies = list()) {
    id <- artifact_check_text(id, "id")
    metadata <- artifact_metadata(id, bytes, media_type, dependencies)
    manifest <- artifact_encode(metadata)
    if (length(manifest) > store$max_revision_bytes) {
      vocabulary_binding_error(
        "Release exceeds the artifact revision byte limit"
      )
    }
    ref <- list(id = metadata$id, revision = artifact_sha(manifest))
    records[[length(records) + 1L]] <<- list(
      id = id,
      bytes = bytes,
      media_type = media_type,
      dependencies = dependencies
    )
    ref
  }
  prepare_named <- function(name, bytes, media_type) {
    prepare(paste0(b$release, ":", name), bytes, media_type)
  }
  refs$bindings <- prepare_named("bindings", source, "application/json")
  refs$vocabulary <- prepare_named(
    "vocabulary",
    vocabulary_bytes,
    "application/json"
  )
  refs$dictionaries <- lapply(seq_along(ids), function(i) {
    list(
      id = ids[[i]],
      source = prepare_named(
        paste0("dictionary:", i),
        dictionary_bytes[[i]],
        "application/yaml"
      ),
      export = prepare_named(
        paste0("export:", i),
        vocabulary_encode(dictionaries[[i]]),
        "application/json"
      )
    )
  })
  published <- vocabulary_release(b, v, dictionaries, vocabulary_hash(source))
  refs$context <- prepare_named(
    "context",
    charToRaw(enc2utf8(paste(published$context, collapse = "\n"))),
    "text/markdown"
  )
  root <- prepare(
    b$release,
    vocabulary_encode(list(
      format = "graft-vocabulary-release/1",
      references = refs
    )),
    "application/json",
    dependencies = vocabulary_dependencies(refs)
  )
  if (
    sum(vapply(records, \(record) length(record$bytes), integer(1))) >
      store$max_bytes
  ) {
    vocabulary_binding_error(
      "Release exceeds the artifact store's aggregate byte limit"
    )
  }
  selection_bytes <- artifact_encode(list(
    format = 1L,
    roots = list(root),
    artifacts = c(list(root), vocabulary_dependencies(refs))
  ))
  if (length(selection_bytes) > 1024^2) {
    vocabulary_binding_error(
      "Release exceeds the artifact selection metadata limit"
    )
  }
  for (record in records) {
    do.call(graft_artifact_save, c(list(store = store), record))
  }
  graft_artifact_select(store, list(root))
}

#' @rdname graft_vocabulary_publish
#' @export
graft_vocabulary_read <- function(store, selection) {
  selected <- graft_artifact_read_selection(store, selection)
  if (length(selected$roots) != 1L) {
    vocabulary_binding_error("A vocabulary selection requires one release root")
  }
  root <- graft_artifact_read(store, selected$roots[[1L]])
  value <- vocabulary_json(root$bytes)
  vocabulary_check_record(value, c("format", "references"), "release")
  if (!identical(value$format, "graft-vocabulary-release/1")) {
    vocabulary_binding_error("Unsupported vocabulary release format")
  }
  refs <- value$references
  vocabulary_check_record(
    refs,
    c("bindings", "vocabulary", "dictionaries", "context"),
    "release references"
  )
  vocabulary_check_array(refs$dictionaries, "dictionary references")
  for (ref in refs$dictionaries) {
    vocabulary_check_record(
      ref,
      c("id", "source", "export"),
      "dictionary reference"
    )
    vocabulary_check_text(ref$id, "dictionary id")
  }
  dependencies <- vocabulary_dependencies(refs)
  for (ref in dependencies) {
    vocabulary_check_record(ref, c("id", "revision"), "artifact reference")
    lapply(ref, vocabulary_check_text, label = "artifact reference")
  }
  # Selection validation already verifies the entire closure; require the root
  # to bind exactly the sources and generated outputs named by its payload.
  keys <- function(x) {
    sort(vapply(
      x,
      \(ref) paste(ref$id, ref$revision, sep = "\n"),
      character(1)
    ))
  }
  if (!identical(keys(root$metadata$dependencies), keys(dependencies))) {
    vocabulary_binding_error(
      "Vocabulary root dependencies differ from its contents"
    )
  }
  read <- function(ref) graft_artifact_read(store, ref)$bytes
  bindings_bytes <- read(refs$bindings)
  vocabulary_bytes <- read(refs$vocabulary)
  b <- vocabulary_json(bindings_bytes)
  vocabulary_companion(b)
  v <- vocabulary_json(vocabulary_bytes)
  if (!identical(vocabulary_hash(vocabulary_bytes), b$vocabulary$sha256)) {
    vocabulary_binding_error(
      "Vocabulary source digest differs from its binding"
    )
  }
  ids <- vapply(refs$dictionaries, \(ref) ref$id, character(1))
  if (
    anyDuplicated(ids) ||
      !identical(ids, vapply(b$dictionaries, \(ref) ref$id, character(1)))
  ) {
    vocabulary_binding_error("Dictionary references differ from the companion")
  }
  dictionaries <- stats::setNames(
    lapply(seq_along(ids), function(i) {
      ref <- refs$dictionaries[[i]]
      if (
        !identical(
          vocabulary_hash(read(ref$source)),
          b$dictionaries[[i]]$sha256
        )
      ) {
        vocabulary_binding_error(
          "Dictionary source digest differs from its binding"
        )
      }
      export <- vocabulary_json(read(ref$export))
      vocabulary_check_record(
        export,
        c("model", "evidence", "package_version", "binary_sha256"),
        "dictionary export"
      )
      vocabulary_check_text(export$package_version, "data-dict package version")
      vocabulary_check_text(export$binary_sha256, "data-dict binary digest")
      if (
        !grepl("^[0-9]+([.-][0-9]+)*$", export$package_version) ||
          !grepl("^[a-f0-9]{64}$", export$binary_sha256)
      ) {
        vocabulary_binding_error("Malformed data-dict validation provenance")
      }
      if (
        !identical(
          export$evidence,
          list(command = "validate-spec", status = 0L)
        )
      ) {
        vocabulary_binding_error("Dictionary validation did not succeed")
      }
      export
    }),
    ids
  )
  vocabulary_validate(b, v, dictionaries)
  published <- vocabulary_release(
    b,
    v,
    dictionaries,
    vocabulary_hash(bindings_bytes)
  )
  if (
    !identical(
      read(refs$context),
      charToRaw(enc2utf8(paste(published$context, collapse = "\n")))
    )
  ) {
    vocabulary_binding_error("Vocabulary context differs from its release")
  }
  published
}

vocabulary_encode <- function(value) {
  charToRaw(enc2utf8(as.character(jsonlite::toJSON(
    value,
    auto_unbox = TRUE,
    null = "null",
    digits = NA
  ))))
}

vocabulary_dependencies <- function(refs) {
  c(
    list(refs$bindings, refs$vocabulary, refs$context),
    unlist(
      lapply(refs$dictionaries, \(ref) list(ref$source, ref$export)),
      recursive = FALSE
    )
  )
}

vocabulary_release <- function(b, v, dictionaries, bindings_digest) {
  published <- list(
    vocabulary = v,
    bindings = b,
    dictionaries = dictionaries,
    references = list(
      vocabulary = b$vocabulary,
      bindings = list(id = b$release, sha256 = bindings_digest),
      dictionaries = b$dictionaries
    )
  )
  published$context <- vocabulary_render_context(published)
  published
}
