# invalid statement shapes and qualifiers fail clearly

    Code
      kg_compile_schema(invalid_schema_path("invalid-mixed-shape.linkml.yaml"),
      withr::local_tempfile(fileext = ".json"))
    Condition
      Error:
      ! Failed to compile LinkML schema `<repo>/tests/testthat/fixtures/invalid-records/invalid-mixed-shape.linkml.yaml`: compile_schema.GraftCompilerError: Concrete statement class MixedClaim inherits from both narrative and semantic statement shapes.
      Run `reticulate::py_last_error()` for details.

---

    Code
      kg_compile_schema(invalid_schema_path("invalid-qualifier.linkml.yaml"), withr::local_tempfile(
        fileext = ".json"))
    Condition
      Error:
      ! Failed to compile LinkML schema `<repo>/tests/testthat/fixtures/invalid-records/invalid-qualifier.linkml.yaml`: compile_schema.GraftCompilerError: Class BadSemanticClaim graft.qualifier_slots references missing slot(s): missing_slot.
      Run `reticulate::py_last_error()` for details.
