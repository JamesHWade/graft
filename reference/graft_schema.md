# Load or compile a Graft schema

`graft_schema()` loads a compiled `.graft.json` manifest or compiles a
LinkML or [data-dict](https://data-dict.tidyverse.org/) contract before
returning an immutable semantic schema object. Data-dict YAML
compilation requires the optional `data-dict` CLI; a resolved
`export-spec` JSON document does not. When `output` is omitted, a
temporary compiled manifest is retained as the schema object's source
path.

## Usage

``` r
graft_schema(path, output = NULL)
```

## Arguments

- path:

  Path to a compiled `.graft.json` manifest, a LinkML YAML schema, a
  `data-dict.yaml` contract, or resolved data-dict JSON.

- output:

  Optional durable `.graft.json` output path when compiling a source
  contract.

## Value

An immutable `GraftSchema` S7 object.
