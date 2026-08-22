# Verify recorded Graft evidence for assistant answers

`graft_verify()` inspects the turns already recorded by an
[ellmer::Chat](https://ellmer.tidyverse.org/reference/Chat.html) and
classifies each completed, text-bearing assistant answer. Verification
is deterministic and offline: it does not call a model, reopen a Graft
store, or authenticate receipt identifiers.

## Usage

``` r
graft_verify(chat)
```

## Arguments

- chat:

  An [ellmer::Chat](https://ellmer.tidyverse.org/reference/Chat.html)
  whose recorded turns should be verified.

## Value

A `graft_verification` data frame with one row per completed answer.
Scalar columns contain `answer_index`, `turn_index`, `answer_text`, and
`label`. List columns contain `reason_codes`, `receipts`, `citations`,
`tool_calls`, and `diagnostics`. A chat without completed answers
returns the same columns with zero rows.

## Details

In this release, successful governed-measure-only evidence is
`"verified"`. Generic Graft reads remain `"untrusted"` with an
`"unmatched_citation"` reason until citation matching is applied.
Unknown, errored, malformed, and unsupported evidence paths fail closed
as `"untrusted"`.
