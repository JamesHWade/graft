#!/usr/bin/env Rscript

script_argument <- grep(
  "^--file=",
  commandArgs(trailingOnly = FALSE),
  value = TRUE
)
if (length(script_argument) != 1L) {
  stop("Run this helper with Rscript.", call. = FALSE)
}

script_path <- normalizePath(
  sub("^--file=", "", script_argument),
  winslash = "/",
  mustWork = TRUE
)
source_dir <- normalizePath(
  file.path(dirname(script_path), ".."),
  winslash = "/",
  mustWork = TRUE
)
destination_dir <- file.path(source_dir, "docs")
instructions_path <- file.path(source_dir, "AGENTS.md")

if (!file.exists(instructions_path)) {
  stop("Expected a root AGENTS.md instruction file.", call. = FALSE)
}
instructions_digest <- unname(tools::md5sum(instructions_path))

# pkgdown 2.2.1 renders unrecognized top-level Markdown files as standalone
# pages. Build from an isolated source view so repository instructions never
# enter the page, search, sitemap, or LLM-document generation pipeline.
staged_source <- tempfile("graft-pkgdown-source-")
dir.create(staged_source)
on.exit(unlink(staged_source, recursive = TRUE, force = TRUE), add = TRUE)

excluded_entries <- c(".git", "AGENTS.md", "docs")
source_entries <- list.files(
  source_dir,
  all.files = TRUE,
  full.names = TRUE,
  no.. = TRUE
)
source_entries <- source_entries[
  !basename(source_entries) %in% excluded_entries
]

copied <- file.copy(
  source_entries,
  staged_source,
  recursive = TRUE,
  copy.mode = TRUE,
  copy.date = TRUE
)
if (!all(copied)) {
  failed <- basename(source_entries[!copied])
  stop(
    "Failed to stage pkgdown source entries: ",
    paste(failed, collapse = ", "),
    call. = FALSE
  )
}

message(
  "Building with pkgdown ",
  as.character(utils::packageVersion("pkgdown"))
)
pkgdown::build_site_github_pages(
  pkg = staged_source,
  dest_dir = destination_dir,
  clean = TRUE,
  install = TRUE,
  new_process = FALSE
)

if (
  !file.exists(instructions_path) ||
    !identical(unname(tools::md5sum(instructions_path)), instructions_digest)
) {
  stop(
    "The root AGENTS.md instruction file changed during the build.",
    call. = FALSE
  )
}

forbidden_outputs <- file.path(destination_dir, c("AGENTS.html", "AGENTS.md"))
forbidden_outputs <- forbidden_outputs[file.exists(forbidden_outputs)]
if (length(forbidden_outputs) > 0L) {
  stop(
    "The site contains forbidden instruction artifacts: ",
    paste(basename(forbidden_outputs), collapse = ", "),
    call. = FALSE
  )
}

indexable_files <- list.files(
  destination_dir,
  pattern = "[.](html|json|md|txt|xml)$",
  recursive = TRUE,
  full.names = TRUE,
  ignore.case = TRUE
)
# Match the instruction file by its exact uppercase name. A case-insensitive
# pattern would also match the lowercase `agents` article, which is ordinary
# site content.
mentions_instructions <- vapply(
  indexable_files,
  \(path) {
    content <- readLines(path, warn = FALSE, encoding = "UTF-8")
    any(grepl("\\bAGENTS[.](md|html)\\b", content))
  },
  logical(1)
)

if (any(mentions_instructions)) {
  offenders <- substring(
    indexable_files[mentions_instructions],
    nchar(destination_dir) + 2L
  )
  stop(
    "The site still refers to AGENTS.md: ",
    paste(offenders, collapse = ", "),
    call. = FALSE
  )
}

message(
  "Verified that AGENTS.md is absent from the published site and indexes."
)
