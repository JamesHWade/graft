# Report Graft's artifact and vocabulary contracts

Consumer contract 4 replaces the public artifact-prefixed interface with
task-oriented verbs and S7 stores and values, without compatibility
aliases. Stored wire formats and exact content identities remain
unchanged. Consumer contract 3.2 adds closed artifact backup bundles
with externally supplied identity receipts and strict restore
verification. Contract 3.1 adds bounded manifests and replacement plans.
These operations do not authorize Forget or backup restore. Consumer
contract 3 removes the native graph store, schema compiler, commit
plans, snapshots, and managed working tree. Artifacts and selections
retain format 1; the cut does not change their bytes or digest
identities. Applications interpret payloads and decide whether evidence
is eligible for use. Graft verifies exact retention and records explicit
host decisions.

## Usage

``` r
graft_contract_version()
```

## Value

A named list of character scalars describing the consumer API and
artifact, manifest, replacement, backup, selection, decision,
vocabulary, and binding formats.

## Examples

``` r
graft_contract_version()
#> $contract
#> [1] "4.0.0"
#> 
#> $artifact
#> [1] "1"
#> 
#> $manifest
#> [1] "graft-artifact-manifest/1"
#> 
#> $replacement
#> [1] "graft-artifact-replacement/1"
#> 
#> $backup
#> [1] "graft-artifact-backup/1"
#> 
#> $selection
#> [1] "1"
#> 
#> $decision
#> [1] "1"
#> 
#> $vocabulary
#> [1] "graft-vocabulary/1"
#> 
#> $bindings
#> [1] "graft-bindings/1"
#> 
#> $vocabulary_release
#> [1] "graft-vocabulary-release/1"
#> 
```
