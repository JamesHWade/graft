test_that("public workflow values are S7 objects", {
  digest <- paste(rep("a", 64L), collapse = "")
  ref <- ArtifactRef(id = "note", revision = digest)
  selection <- ArtifactSelection(
    id = digest,
    roots = list(ref),
    artifacts = list(ref)
  )
  decision <- Decision(
    id = digest,
    sequence = 1L,
    stream = "stream",
    key = "request-1",
    previous = NULL,
    action = "accept",
    selection = digest,
    actor = "reviewer",
    reason = "reviewed",
    purpose = "research"
  )
  artifact <- Artifact(
    ref = ref,
    bytes = charToRaw("hello"),
    media_type = "text/plain",
    dependencies = list(ref),
    data = "hello"
  )
  recall <- Recall(
    status = "accepted",
    decision = decision,
    selection = selection,
    roots = list(artifact),
    artifacts = list(artifact)
  )

  expect_identical(S7::S7_inherits(ref, ArtifactRef), TRUE)
  expect_identical(S7::S7_inherits(artifact, Artifact), TRUE)
  expect_identical(S7::S7_inherits(selection, ArtifactSelection), TRUE)
  expect_identical(S7::S7_inherits(decision, Decision), TRUE)
  expect_identical(S7::S7_inherits(recall, Recall), TRUE)
  expect_identical(artifact@data, "hello")
  expect_identical(artifact@bytes, charToRaw("hello"))
  expect_identical(decision@selection, digest)
  expect_match(capture.output(print(ref)), "ArtifactRef")
  expect_match(capture.output(print(recall)), "accepted")
})

test_that("public values validate their shape and do not provide dollar access", {
  digest <- paste(rep("b", 64L), collapse = "")
  ref <- ArtifactRef(id = "note", revision = digest)

  expect_error(
    ArtifactRef(id = "", revision = digest),
    class = "graft_value_error"
  )
  expect_error(
    ArtifactSelection(
      id = digest,
      roots = list(ref),
      artifacts = list(list(ref))
    ),
    class = "graft_value_error"
  )
  expect_error(
    Artifact(
      ref = ref,
      bytes = charToRaw("hello"),
      media_type = "text/plain",
      dependencies = list(ref),
      data = 1
    ),
    class = "graft_value_error"
  )
  expect_error(
    ref$id,
    class = "error",
    regexp = "Can't get S7 properties"
  )
})
