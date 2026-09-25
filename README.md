# graft <img src="man/figures/logo.png" align="right" height="138" alt="Graft logo" />

Graft saves project knowledge and its evidence so your R apps and agents can
use it in later conversations and workflows. You can keep a finding, record
which definition your team agreed to use, and inspect the history when it changes.

Suppose you're building an analytics assistant with ellmer and shinychat.
Your team agrees that an "active customer" has a paid account and used the product
in the last 30 days. With Graft, your app can save that definition and its source,
record your review, and let a fresh chat look it up. When the team changes the
window to 60 days, you can review the correction while preserving the earlier
version and its evidence.

Your application chooses what to save and who may use it. Graft stores that
knowledge and its history across sessions, where the model can look it up to
answer a question.

## Try a project assistant

The package includes a small Shiny app with a project notebook beside the chat.
The default preview uses real Graft storage and scripted replies. You can try
it without calling a model.

```r
pak::pak(c("JamesHWade/graft", "ellmer", "shinychat", "shiny", "bslib"))

# Keep the notebook in your project, including after the app stops.
Sys.setenv(GRAFT_DEMO_STORE = file.path(getwd(), "project-memory"))
shiny::runApp(system.file("examples", "project-memory", package = "graft"))
```

1. Read the proposed definition and source, then choose Review and save.
2. Ask "How do we count an active customer?"
3. Start a New conversation and ask again. The saved knowledge is still there.
4. Change the definition and source to use 60 days, review the correction,
   and ask again. The next conversation retrieves the updated definition.
5. Stop and restart the app with the same store path to reopen the notebook.

For a live ellmer agent, configure `OPENAI_API_KEY`, set
`Sys.setenv(GRAFT_DEMO_LIVE = "true")`, and relaunch. The agent gets a read-only
memory tool; the notebook's review controls decide what it may remember.
Live mode sends prompts and retrieved memory to the configured model provider.

[Build the assistant step by step](https://jameshwade.github.io/graft/articles/getting-started.html)
The guide shows the Graft calls, the ellmer tool, and the shinychat connection.
The [complete example source](inst/examples/project-memory/) is included for you
to copy and adapt.

## Where you could use it

| Your project | Knowledge worth keeping | What a later task can recover |
|---|---|---|
| A project chat assistant | Reviewed metric definitions and team decisions | The current definition and the exact source it was based on |
| An analysis or research workflow | A conclusion, report, table, or figure with its inputs | The original output and its retained dependencies |
| Several agents working on the same domain | Shared concepts and field meanings bound to a data-dict release | The same vocabulary, even after the original dictionary changes |

You can save plain text, JSON, a rendered report, or other bytes. Supply text or
raw bytes and link to the exact revisions of any evidence it depends on. Graft
keeps each revision unchanged. You can group related artifacts into a typed
selection and record whether your application accepts or withdraws that
selection for a particular purpose.

To revisit an earlier conclusion, read its exact references. These reads return
typed `Artifact` values. To find what a task should use now, recall the current
accepted result. Recall checks both the review decision and the stored contents.

## Save a result with its evidence

Start with a fresh directory and ordinary text:

```r
library(graft)
store <- graft_store("analysis-memory", create = TRUE)
source <- graft_save(store, "Handbook: use a 30-day activity window.", "handbook")
note <- graft_save(
  store, "An active customer used the product in the past 30 days.",
  id = "active-customer", dependencies = source
)
graft_read(store, note)@data
```

Reopen it later with `graft_store("analysis-memory")`. Saving a correction under
the same ID creates a new revision; the original reference still reads the
original content. Use `graft_accept()` to record a review and `graft_recall()` to
retrieve the current accepted result, as shown in the getting-started guide.

## Apply it to your app

Start with one kind of knowledge your users repeatedly need. For example, add a
"Save to project memory" action to an existing assistant, then expose
`graft_tool()` for one fixed stream and purpose. Your app decides which project or
user the memory belongs to, provides the review action, and checks access on
each call. ellmer manages the model and tools; shinychat presents the conversation.

As your notebook grows, your application can keep a catalog or search index to
choose relevant notes, then use Graft to verify the saved selection.
For shared terminology, [publish a vocabulary](https://jameshwade.github.io/graft/articles/shared-vocabulary.html)
bound to a data-dict dictionary.

## Further reading and current scope

- [Getting started: give a chat agent project memory](https://jameshwade.github.io/graft/articles/getting-started.html)
- [Artifacts, evidence, and review history](https://jameshwade.github.io/graft/articles/persistent-artifacts.html)
- [Shared concepts and vocabulary](https://jameshwade.github.io/graft/articles/shared-vocabulary.html)
- [Back up and restore a notebook](https://jameshwade.github.io/graft/articles/artifact-backups.html)
- [Architecture and integration requirements](https://jameshwade.github.io/graft/articles/compatibility.html)

Graft is pre-production. A local store uses trusted files, and several R
processes can write to it on a file system that honours advisory locks (many
network file systems do not). For PostgreSQL, your application owns the transaction in which Graft
reads and writes. The demo uses `eligible = TRUE` for one trusted local user.
Before deploying to several users, your app needs to identify them, check their
access, and decide how long to keep their data. Permanent Forget and recovery
from retired backups remain active work.
