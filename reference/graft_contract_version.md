# Report the Graft consumer contract version

`graft_contract_version()` returns the versions a downstream package can
pin against instead of hashing Graft's namespace or checking a git
commit. The `contract` entry follows semantic versioning for the
exported functions, their arguments, and the shapes of the values they
return: a change that breaks an existing consumer increments the major
component, a compatible addition increments the minor component, and a
behavior fix increments the patch component. The remaining entries name
the persisted formats a consumer may store, compare, or serialize.

## Usage

``` r
graft_contract_version()
```

## Value

A named list of character scalars: `contract`, `store_format`, `plan`,
`snapshot_schema`, `manifest`, and `okf`.

## Examples

``` r
graft_contract_version()$contract
#> [1] "0.4.0"
```
