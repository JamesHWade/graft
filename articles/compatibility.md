# Supported integrations

## Current consumer contract

``` r

graft::graft_contract_version()
```

    ## $contract
    ## [1] "4.1.0"
    ## 
    ## $artifact
    ## [1] "1"
    ## 
    ## $manifest
    ## [1] "graft-artifact-manifest/1"
    ## 
    ## $replacement
    ## [1] "graft-artifact-replacement/1"
    ## 
    ## $backup
    ## [1] "graft-artifact-backup/1"
    ## 
    ## $selection
    ## [1] "1"
    ## 
    ## $decision
    ## [1] "1"
    ## 
    ## $vocabulary
    ## [1] "graft-vocabulary/1"
    ## 
    ## $bindings
    ## [1] "graft-bindings/1"
    ## 
    ## $vocabulary_release
    ## [1] "graft-vocabulary-release/1"

Graft requires R 4.3 or later and imports S7, digest, fs, jsonlite, and
rlang. Publishing vocabulary also requires the data-dict R package and
CLI. Reading a published release requires neither the CLI nor the
original dictionary files.

The consumer contract is **4.1.0**. Everyday work uses the task verbs
[`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md),
[`graft_save()`](https://jameshwade.github.io/graft/reference/graft_save.md),
[`graft_read()`](https://jameshwade.github.io/graft/reference/graft_read.md),
[`graft_accept()`](https://jameshwade.github.io/graft/reference/graft_accept.md),
[`graft_withdraw()`](https://jameshwade.github.io/graft/reference/graft_withdraw.md),
[`graft_recall()`](https://jameshwade.github.io/graft/reference/graft_recall.md),
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md),
and
[`graft_streams()`](https://jameshwade.github.io/graft/reference/graft_streams.md),
along with the S7 store and value classes. The old artifact-prefixed
exports have been removed, and no compatibility aliases exist. Artifact
bytes, selection formats, and content identities remain unchanged.

`DESCRIPTION` pins the dictionary integration to the validated data-dict
source revision. Commons is application-owned. Pass retained vocabulary
context and validated data to its public source API. Graft does not
maintain a Commons connection adapter or copy executable agent tools.

Applications such as Tempest and Rill adopt this public API in their
integration layers. They choose which evidence to retain, validate their
domain results, and authorize reuse. [Issue
\#91](https://github.com/JamesHWade/graft/issues/91) tracks their
contract 4 migration.

## Native chat classes

[`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md)
returns an ordinary
[`ellmer::ToolDef`](https://ellmer.tidyverse.org/reference/ToolDef.html).
Register it with an ellmer chat using `chat$register_tool()`. Each
invocation returns a native
[`ellmer::ContentToolResult`](https://ellmer.tidyverse.org/reference/Content.html)
and may include
[`shinychat::tool_result_display()`](https://posit-dev.github.io/shinychat/r/reference/tool_result_display.html)
metadata. The tool fixes the store, stream, and purpose when it is
constructed, then calls the application’s eligibility function on every
invocation.

The adapter receives Graft’s S7 store as a separate object. The store
does not inherit from ellmer’s chat class or implement shinychat’s
conversation store. Those packages retain control of model calls, tool
execution, and conversation state. The store persists only explicit
artifact bytes and canonical records. It never serializes live chats,
tools, or database connections.

## Hard cut from native graph APIs

The graph store, schema compiler, plans, receipts, snapshots,
calculation engine, and managed OKF tree have been removed. This package
cannot open native graph stores or snapshots. Consumer upgrades remove
those paths and old persisted product schemas. Graft artifact,
selection, decision, and vocabulary formats retain their existing
content identities. Historical ADRs and migration notes describe the
earlier architecture. They remain historical records and are not
supported recipes.
