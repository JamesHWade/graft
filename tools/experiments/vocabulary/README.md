# Portable vocabulary experiment

Issue [#60](https://github.com/JamesHWade/graft/issues/60). Run offline from the
repository root after installing the pinned dependency environment described in
the [results note](../../../specs/2026-09-16-vocabulary-experiment.md):

```sh
Rscript tools/experiments/vocabulary/run.R /tmp/vocabulary-results
```

Set `R_LIBS_USER` to the experiment library and `DATA_DICT` to the pinned CLI
binary. Execution makes no network or model calls and uses temporary directories
for destructive test candidates. The optional output path receives `results.json`,
two published JSON bundles and generated Markdown context.

- `publisher.R` owns companion validation and generation. It uses public
  `datadict::dd_run()` validation/export and never parses dictionary YAML or
  evaluates expressions.
- `fixtures/v1` and `fixtures/v2` contain independently authored laboratory
  dictionaries, one shared vocabulary, and pinned companion bindings.
- `run.R` executes plain R consumption, Commons public constructor consumption,
  historical replay and 16 focused success/failure cases.
- `observed/` contains the recorded run's result and generated context. Rebuild
  output in a separate directory; compare it before replacing recorded evidence.

The format is deliberately local to this experiment. `publish_bindings()` returns
`references` with exact vocabulary, binding and dictionary IDs/digests for the
artifact manifest. References must travel with preserved bytes; hashes alone do
not preserve an artifact. `render_context()` includes these IDs in the body.

No Graft store, public Graft API, chat object, join planner, reasoner, permission
system or expression compiler is introduced. Commons constructor acceptance is
the boundary tested here; model/tool retrieval belongs to experiment #62.
