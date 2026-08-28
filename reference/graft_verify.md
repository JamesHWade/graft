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
`tool_calls`, and `diagnostics`. Each citation records its tool-call
index, candidate type and text, and matched result path and text. A chat
without completed answers returns the same columns with zero rows.

## Details

Successful governed-calculation-only evidence is `"verified"`.
Successful generic Graft reads are `"cited"` only when every result is
independently matched to an explicit quotation or Markdown blockquote in
the answer. A generic read caps mixed calculation and generic evidence
at `"cited"`. Unknown, errored, malformed, unsupported, and
citation-unmatched evidence paths fail closed as `"untrusted"`.

Verification classifies the recorded evidence path. It does not
fact-check the answer or cryptographically authenticate receipt
identifiers.
