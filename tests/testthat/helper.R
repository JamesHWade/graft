graft_checkout <- function() {
  if (pkgload::is_dev_package("graft")) {
    getNamespaceInfo(asNamespace("graft"), "path")
  } else {
    NULL
  }
}
