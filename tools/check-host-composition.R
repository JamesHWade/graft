#!/usr/bin/env Rscript
# Dependency installation is caller-owned. All model transport is loopback-only.
for (package in c("ellmer", "deputy", "dsprrr", "callr", "httpuv")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("Install the optional integration dependency: ", package)
  }
  description <- utils::packageDescription(package)
  print(description[intersect(
    c("Package", "Version", "RemoteSha"),
    names(description)
  )])
}
devtools::test(
  filter = "^(host-composition|narrative-knowledge|reuse-basis|reuse-eligibility)$",
  stop_on_failure = TRUE
)
