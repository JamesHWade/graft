# Load or compile a Graft schema

`graft_schema()` turns a [data-dict](https://data-dict.tidyverse.org/)
or LinkML source into the contract used to validate records, or loads an
existing `.graft.json` contract. A trusted resolved data-dict
`export-spec` document compiles in R. Data-dict YAML requires the
optional `data-dict` CLI, while LinkML YAML requires Python and
`linkml-runtime`. When compiling a source contract without `output`,
Graft retains a temporary compiled manifest for the returned schema
object. Loading an existing `.graft.json` keeps its original path.

## Usage

``` r
graft_schema(path, output = NULL)
```

## Arguments

- path:

  Path to a data-dict YAML or resolved JSON contract, a LinkML YAML
  schema, or a compiled `.graft.json` manifest.

- output:

  Optional durable `.graft.json` output path when compiling a source
  contract.

## Value

An immutable `GraftSchema` S7 object.

## Examples

``` r
dictionary <- system.file(
  "extdata",
  "team-directory.data-dict.json",
  package = "graft",
  mustWork = TRUE
)
schema <- graft_schema(dictionary)
schema@name
#> [1] "team_directory"
```
