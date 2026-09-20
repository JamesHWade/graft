# Supported integrations

## Current consumer contract

``` r

graft::graft_contract_version()
```

    ## $contract
    ## [1] "3.2.0"
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

Graft requires R 4.3 or later and imports digest, fs, jsonlite, and
rlang. Publishing vocabulary additionally requires the data-dict R
package and CLI; reading a published release requires neither the CLI
nor original dictionary files.

The dictionary integration is pinned in `DESCRIPTION` to the validated
data-dict source revision. Commons is host-owned: pass retained
vocabulary context and validated data to its public source API. Graft
does not maintain a Commons connection adapter or copy executable agent
tools.

Tempest publishes research through the artifact API and supplies its own
scientific validation and admission callback. scans reads Tempest’s
public trajectory projection rather than reconstructing Graft’s storage
protocol.

## Hard cut from native graph APIs

The graph store, schema compiler, plans, receipts, snapshots,
calculation engine, and managed OKF tree have been removed. Native graph
stores and snapshots cannot be opened by this package. Consumer upgrades
remove those paths together with old persisted product schemas. Graft
artifact, selection, decision, and vocabulary formats retain their
existing content identities.
