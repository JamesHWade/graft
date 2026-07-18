# graft 0.0.0.9000

* `kg_connect_duckdb()`, `kg_init()`, and `kg_disconnect()` provide an
  ownership-aware DuckDB store lifecycle with manifest-driven initialization
  and structural schema protection.
* `kg_store_info()` and `kg_capabilities()` inspect DuckDB stores without
  requiring Python.
* `kg_compile_schema()` compiles LinkML schemas into deterministic, portable
  graft manifests.
* `kg_schema()`, `kg_classes()`, `kg_slots()`, `kg_enums()`, and
  `kg_schema_info()` load and inspect manifests without Python.
* `kg_schema_diff()` reports structural schema changes.
