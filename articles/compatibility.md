# Supported integrations

## Current consumer contract

``` r

graft::graft_contract_version()
```

    ## $contract
    ## [1] "4.0.0"
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
rlang. Publishing vocabulary additionally requires the data-dict R
package and CLI; reading a published release requires neither the CLI
nor original dictionary files.

The consumer contract is **4.0.0**. Everyday work uses the task verbs
[`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md),
[`graft_save()`](https://jameshwade.github.io/graft/reference/graft_save.md),
[`graft_read()`](https://jameshwade.github.io/graft/reference/graft_read.md),
[`graft_accept()`](https://jameshwade.github.io/graft/reference/graft_accept.md),
[`graft_withdraw()`](https://jameshwade.github.io/graft/reference/graft_withdraw.md),
[`graft_recall()`](https://jameshwade.github.io/graft/reference/graft_recall.md),
and
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md),
with S7 store and value classes. The old artifact-prefixed exports are
removed; there are no compatibility aliases. Artifact bytes, selection
formats, and content identities remain unchanged.

The dictionary integration is pinned in `DESCRIPTION` to the validated
data-dict source revision. Commons is host-owned: pass retained
vocabulary context and validated data to its public source API. Graft
does not maintain a Commons connection adapter or copy executable agent
tools.

Applications such as Tempest and Rill adopt this public API in their own
integration layers. They choose the evidence to retain, validate their
domain results, and authorize reuse. Their contract 4 migration is
tracked in [issue \#91](https://github.com/JamesHWade/graft/issues/91).

## Native chat classes

[`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md)
returns an ordinary
[`ellmer::ToolDef`](https://ellmer.tidyverse.org/reference/ToolDef.html);
register it with an ellmer chat using `chat$register_tool()`. Each
invocation returns a native
[`ellmer::ContentToolResult`](https://ellmer.tidyverse.org/reference/Content.html),
with optional
[`shinychat::tool_result_display()`](https://posit-dev.github.io/shinychat/r/reference/tool_result_display.html)
metadata. The tool fixes the store, stream, and purpose when constructed
and calls the application’s eligibility function on every invocation.

Graft’s S7 store is a separate object passed into this adapter. It does
not inherit from ellmer’s chat class or implement shinychat’s
conversation store. Those packages keep control of model calls, tool
execution, and conversation state. Only explicit artifact bytes and
canonical records are persisted; live chats, tools, and database
connections are never serialized into the store.

## Hard cut from native graph APIs

The graph store, schema compiler, plans, receipts, snapshots,
calculation engine, and managed OKF tree have been removed. Native graph
stores and snapshots cannot be opened by this package. Consumer upgrades
remove those paths together with old persisted product schemas. Graft
artifact, selection, decision, and vocabulary formats retain their
existing content identities. Historical ADRs and migration notes
describe the earlier architecture; they are retained as history rather
than supported recipes.
