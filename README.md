# graft

graft is a table-native knowledge layer for R. It compiles a LinkML semantic
contract into a portable JSON manifest that describes concrete record classes,
relational tables, identity policies, validation invariants, and graph
projections.

Python and `linkml-runtime` are required only to compile a schema. Loading and
inspecting a committed manifest is pure R/JSON:

```r
library(graft)

schema <- kg_schema("tempest-artifacts.graft.json")
kg_classes(schema)
kg_slots(schema, "Claim")
kg_schema_info(schema)
```

The initial package slice focuses on the semantic contract and deterministic
compiler. DuckDB storage and retrieval build on the compiled manifest in later
milestones.
