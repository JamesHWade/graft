# Graft Coworker

Graft Coworker is an installable local work-surface example inspired by
[OpenWorker](https://github.com/andrewyng/openworker). It implements the
smallest useful version of the same outcome-first loop in the R ecosystem:

```text
request -> plan -> reconcile evidence -> prepare deliverable
        -> await approval -> publish file -> remember accepted outcome
```

It is not a port of OpenWorker and does not copy its implementation. The
example maps the product contract onto components that already fit together:

- **shinychat and ellmer** provide the multi-user-safe chat surface and tool
  loop;
- **dsprrr** provides one planner contract with interchangeable deterministic
  and model-backed implementations;
- **Tempest** owns the typed workflow, artifacts, ordered events, and
  artifact-approval pause;
- **Graft** preserves only approved runs, deliverables, decisions, source
  links, and workspace memory; and
- **Shiny and bslib** provide the work view, approval inbox, memory ledger, and
  activity view.

## Run it

From a development checkout, load the current Tempest development version
before Graft:

```r
devtools::load_all("../tempest")
devtools::load_all(".")
options(tempest.chat = "openai/gpt-5-mini")
shiny::runApp("inst/examples/coworker/app")
```

`tempest.chat` may instead be an ellmer `Chat` object. The app deep-clones the
configured client for each browser session and uses a separate clone for the
dsprrr planner.

From an installed package:

```r
example <- system.file(
  "examples",
  "coworker",
  package = "graft",
  mustWork = TRUE
)
shiny::runApp(file.path(example, "app"))
```

Use **Run provider-free example** to exercise the complete workflow without a
model key. The same dsprrr module contract is used, but its reference planner
is an ordinary deterministic R function.

## What the reference request proves

The synthetic Project Atlas bundle contains bounded GitHub, Jira, and Slack
source snapshots. The reference request asks for a release-readiness brief and
team update.

1. The planner receives the request, source snapshots, and earlier accepted
   Graft memory.
2. A Tempest workflow produces a structured work plan and a Markdown outcome
   package.
3. The outcome artifact remains `awaiting_approval`; its exporter has not run,
   no file exists, and no draft record has entered Graft.
4. Rejection fails the run without publishing or writing memory.
5. Approval resumes the same run without rerunning the planner, exports the
   reviewed Markdown unchanged, and atomically ingests the run, deliverable,
   approval, and memory into Graft.
6. The next request receives that accepted memory as continuity context.

The app's **Inbox**, **Memory**, and **Activity** views expose those boundaries
directly.

## Local data

The default data directory is:

```r
file.path(tools::R_user_dir("graft", "data"), "coworker")
```

Set either `options(graft.coworker.data_dir = "/path")` or the
`GRAFT_COWORKER_HOME` environment variable to choose another directory. The
directory contains:

- `coworker.duckdb`, the durable Graft store; and
- `deliverables/`, files exported after approval.

The reference app is a local single-user host. Running multiple browser
sessions against one DuckDB path is outside this example's concurrency
contract.

## Extension boundary

The current slice deliberately stops short of OpenWorker's full breadth. It
does not yet provide a desktop shell, background scheduling, OAuth connector
catalog, durable chat transcripts, voice input, MCP client, or real Slack and
calendar writes.

Those are host concerns, not missing Graft record APIs. A production host can
replace the reference bundle with authenticated read adapters and add
side-effecting Tempest capabilities whose exact targets are shown on the same
approval card. A second concrete use case should precede any new public Graft
or Tempest API.

## Layout

- `schema/coworker.linkml.yaml` defines the application-owned memory contract.
- `schema/coworker.graft.json` is its committed compiled manifest.
- `corpus/project-atlas.json` is the bounded synthetic source bundle.
- `R/planner.R` defines the shared dsprrr planning contract.
- `R/workflow.R` defines the typed Tempest work-product lifecycle.
- `R/worker.R` owns local storage, approval resolution, and approved ingestion.
- `app/` contains the shinychat and bslib host.
