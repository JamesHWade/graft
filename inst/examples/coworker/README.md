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
dsprrr planner. Internally, Coworker creates a `tempest_config()` and preserves
Tempest's precedence rules: an explicitly supplied configuration wins over the
ambient `tempest.chat` default, and an explicit `chat_fn` wins over both. The
Coworker assistant and planner map to Tempest's `coordinator` and `writer`
roles, respectively.

For a per-app configuration, set a complete Tempest configuration before
launch:

```r
options(
  graft.coworker.tempest_config = tempest::tempest_config(
    models = list(
      coordinator = "anthropic/claude-sonnet-4-20250514",
      writer = "openai/gpt-5-mini"
    )
  )
)
```

This also supports Tempest's `chat_fn` escape hatch for an internal provider or
other custom ellmer client.

## Add tools

Coworker always loads its governed `prepare_outcome` and `recall_memory` tools.
Add any number of ellmer tools with a list:

```r
my_tool <- ellmer::tool(
  function(package) as.character(utils::packageVersion(package)),
  "Return the installed version of an R package.",
  arguments = list(
    package = ellmer::type_string("An installed R package name.")
  ),
  name = "installed_package_version"
)

options(graft.coworker.tools = list(my_tool))
```

Use a provider function when tools need the current Shiny session or Coworker
worker. It receives a context list with `worker`, `input`, `revision`,
`session`, and `example_dir`:

```r
options(
  graft.coworker.tools = function(context) {
    list(my_session_tool(context$session))
  }
)
```

The optional [btw](https://github.com/posit-dev/btw) integration makes a broad
R-aware tool belt available with one option:

```r
install.packages("btw")
options(graft.coworker.btw = "read_only")
```

The read-only profile discovers the tools provided by the installed btw
version and admits environment, documentation, file-reading, Git inspection,
session, skill, CRAN, IDE, and web-reading tools. It excludes file edits,
package execution, arbitrary R execution, Git mutations, GitHub API access,
and subagents. Use btw group or tool names for an intentional subset:

```r
options(graft.coworker.btw = c("docs", "env", "sessioninfo"))
```

`options(graft.coworker.btw = "all")` exposes every locally available btw tool
and should be reserved for a trusted single-user environment. Directly
registered mutating tools do not pass through Coworker's Tempest approval
card. Production write tools should instead be implemented as typed Tempest
capabilities so the exact action and target can be reviewed before execution.
Coworker rejects duplicate tool names rather than silently replacing a tool.

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
calendar writes. Its ellmer registry can already consume arbitrary local tool
collections, including btw, without turning those tools into Graft APIs.

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
