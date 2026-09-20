# Project memory assistant

This small Shiny app shows one trusted local user saving a reviewed project
definition for later conversations. The note and its exact source excerpt are
stored as immutable Graft artifacts. A review records which exact note and
source may be consulted. A correction or withdrawal changes the current
decision, and the app resets the chat so an earlier answer is not silently
carried forward.

Install the optional example packages once if needed:

```r
install.packages(c("shiny", "bslib", "shinychat", "ellmer"))
```

Run it from a checkout with:

```r
pkgload::load_all()
shiny::runApp("inst/examples/project-memory")
```

For an installed Graft package, run the example directory returned by
`system.file("examples", "project-memory", package = "graft")` instead.

The default is an offline preview. It uses the real local Graft store and
`shinychat` UI, but every reply is a deterministic lookup and it makes no
model calls. The store defaults to
`tools::R_user_dir("graft", "data")/project-memory-demo`. Set
`GRAFT_DEMO_STORE` to an absolute local path to choose another store.

The prefilled definition and handbook excerpt are fictional sample data.
Replace both with knowledge and evidence from your own project.

To try the story:

1. Edit the reviewed note and exact source excerpt.
2. Choose **Review and save**.
3. Ask **How do we count an active customer?**.
4. Stop and restart the app using the same store path to see that the reviewed
   memory persists.
5. Choose **New conversation**, then ask the question again.
6. Change the definition and source from 30 to 60 days, save it, and ask
   again.
7. Choose **Stop using this note** to withdraw the current definition.

For an optional live run, set `GRAFT_DEMO_LIVE=true` and configure
`OPENAI_API_KEY` in the process environment before starting the app. Live
responses use `ellmer::chat_openai()` and a read-only `recall_project_memory`
tool; the user prompt and the tool's retrieved memory are sent to the model
provider for that response. The tool reports when memory is missing or
withdrawn, and the prompt forbids treating tool content as instructions. The
example does not persist a chat transcript and is not a multi-user
authentication layer.
