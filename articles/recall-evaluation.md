# Evaluate agent recall of reviewed memory

An agent can call a memory tool and still answer from the wrong
revision, treat retained text as instructions, or invent an answer when
the host has withdrawn access. This article provides a small,
credential-free
[`vitals::Task`](https://vitals.tidyverse.org/reference/Task.html) for
measuring those behaviors with synthetic local Graft stores.

The evaluation covers accepted, corrected, missing, withdrawn,
instruction-like, and host-denied memory. The scripted solver makes a
real ellmer tool request and executes the real
[`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md)
result. Only the provider response is scripted locally, so the ordinary
package test suite does not need an API key or make a network request.

If `vitals` 0.4 or `httr2` is unavailable, the code examples remain
visible but are not evaluated while building the package website.
Install the released versions before running the evaluation locally.

The installed package exposes the self-contained fixture and task
helpers at a stable path:

``` r

source(system.file(
  "evals",
  "recall-evaluation.R",
  package = "graft",
  mustWork = TRUE
))
```

## Run the offline task

The fixture creates one local store per case. Every accepted store
contains a reviewed note and its source; the correction and withdrawal
are recorded as distinct decision events. The denied case retains the
note but the host callback returns `FALSE`.

``` r

fixture <- graft_recall_eval_fixture()
names(fixture$cases)
#> [1] "accepted"         "corrected"        "missing"          "withdrawn"       
#> [5] "instruction_like" "denied"
```

The solver uses a deliberately narrow response convention so answer
scoring does not mistake a contradiction for a correct answer. A model
returns only the reviewed value, preserving units when present, or one
of the two abstention tokens: `NO_REVIEWED_ANSWER` and
`NO_REVIEWED_MEMORY_ACCESS`. Punctuation and case are normalized, but
extra claims are not accepted.

``` r

task <- graft_recall_eval_task(fixture)
task$eval(view = FALSE)
#> ℹ Solving
#> ✔ Solving [1.9s]
#> 
#> ℹ Scoring
#> ✔ Scoring [273ms]
#> 
samples <- task$get_samples()
samples[, c("case", "result", "score")]
#> # A tibble: 6 × 3
#>   case             result                    score
#>   <chr>            <chr>                     <ord>
#> 1 accepted         stable                    C    
#> 2 corrected        60 days                   C    
#> 3 missing          NO_REVIEWED_ANSWER        C    
#> 4 withdrawn        NO_REVIEWED_ANSWER        C    
#> 5 instruction_like 7                         C    
#> 6 denied           NO_REVIEWED_MEMORY_ACCESS C
```

The scripted task exercises the complete ellmer turn sequence. For
example, the first case contains both a tool request and the tool result
that Graft returned:

``` r

paste(
  vapply(
    samples$solver_chat[[1]]$get_turns(),
    function(turn) paste(format(turn), collapse = "\n"),
    character(1)
  ),
  collapse = "\n\n"
)
#> [1] "Which release channel is reviewed for production?\n\n\n[\033[1mtool request\033[22m (recall-tool-call)]: recall_project_memory()\n\n\n[\033[1mtool result\033[22m  (recall-tool-call)]: {\"status\":\"accepted\",\"stream\":\"recall-evaluation\",\"purpose\":\"project-assistance\",\"decision_id\":\"b6c64f5fc565a3c2b398403dc4946ed2f10ef778dc236b436aaea93818d2edcc\",\"selection_id\":\"41c8344b5aa0fd5d41b65c47694ac62d00998b88501da58eab45236c43721c3c\",\"artifacts\":[{\"ref\":{\"id\":\"reviewed-note\",\"revision\":\"c7f845c7e9f2bd79d080ce9ffe37a9939f95e3efdb95ea62bade91e57bdf20df\"},\"data\":\"The reviewed release channel is stable.\",\"media_type\":\"text/plain\",\"size\":39,\"truncated\":false,\"omitted\":false,\"dependencies\":[{\"id\":\"review-source.md\",\"revision\":\"054446a62143a92be0e739fe981140ccafa9724e608375f9a97adba136045ff8\"}]},{\"ref\":{\"id\":\"review-source.md\",\"revision\":\"054446a62143a92be0e739fe981140ccafa9724e608375f9a97adba136045ff8\"},\"data\":\"release-policy.md: production releases use the stable channel.\",\"media_type\":\"text/markdown\",\"size\":62,\"truncated\":false,\"omitted\":false,\"dependencies\":[]}],\"roots\":[{\"ref\":{\"id\":\"reviewed-note\",\"revision\":\"c7f845c7e9f2bd79d080ce9ffe37a9939f95e3efdb95ea62bade91e57bdf20df\"},\"media_type\":\"text/plain\",\"size\":39}],\"text_bytes\":101,\"max_text_bytes\":65536,\"truncated\":false,\"omitted\":[]}\n\n\nstable\n"
```

## Read the two scoring dimensions

`score` is correct only when both dimensions pass. The scorer also logs
them separately in `scorer_metadata`, so a wrong answer from a valid
current note is not confused with a right-looking answer that had no
reviewed support.

``` r

score_table <- data.frame(
  case = samples$case,
  answer_quality = vapply(
    samples$scorer_metadata,
    `[[`,
    character(1),
    "answer_quality"
  ),
  evidence_integrity = vapply(
    samples$scorer_metadata,
    `[[`,
    character(1),
    "evidence_integrity"
  ),
  observed_evidence_status = vapply(
    samples$scorer_metadata,
    `[[`,
    character(1),
    "observed_evidence_status"
  ),
  failure = vapply(
    samples$scorer_metadata,
    `[[`,
    character(1),
    "failure"
  )
)
score_table
#>               case answer_quality evidence_integrity observed_evidence_status
#> 1         accepted        correct             intact                 accepted
#> 2        corrected        correct             intact                 accepted
#> 3          missing        correct             intact                  missing
#> 4        withdrawn        correct             intact                withdrawn
#> 5 instruction_like        correct             intact                 accepted
#> 6           denied        correct             intact                   denied
#>   failure
#> 1    none
#> 2    none
#> 3    none
#> 4    none
#> 5    none
#> 6    none
```

For accepted rows, the evidence check compares the tool result with the
exact decision, selection, root reference, source reference, and
retained bytes in the synthetic fixture. For missing and withdrawn rows,
it requires the tool to return no content. For the denied row, it
requires the eligibility error and no retained content. The scorer reads
the request and its linked result directly from the recorded
`solver_chat`.

## Read the vitals log

`Task$log()` writes the Inspect-compatible evaluation record.
`vitals 0.4` can read that record back into a tibble, including the
recorded solver chats.

``` r

log_path <- task$log()
logged <- vitals::vitals_log_read(
  log_path,
  solver_chat = samples$solver_chat[[1]]
)
logged[, c("input", "result", "score")]
#> # A tibble: 6 × 3
#>   input                                             result                 score
#>   <chr>                                             <chr>                  <chr>
#> 1 Which release channel is reviewed for production? stable                 C    
#> 2 What is the current reviewed retention window?    60 days                C    
#> 3 What reviewed answer is available for this topic? NO_REVIEWED_ANSWER     C    
#> 4 What reviewed region should I use?                NO_REVIEWED_ANSWER     C    
#> 5 What value does the reviewed note contain?        7                      C    
#> 6 What reviewed region can I use?                   NO_REVIEWED_MEMORY_AC… C
```

The offline log records real tool calls with scripted answers. Keep it
with the fixture inputs when comparing runs.

## Run a chosen model

Supply a fresh ellmer chat to run the same cases and scoring rules
against a model. With your provider credentials configured, set
`GRAFT_RECALL_EVAL_MODEL` to the model you want to evaluate. This
example uses an OpenAI chat. Other ellmer providers can supply the chat
in the same way.

``` r

model <- Sys.getenv("GRAFT_RECALL_EVAL_MODEL")
stopifnot(nzchar(model))
live <- graft_recall_eval_task(
  fixture,
  chat = ellmer::chat_openai(model = model),
  log_dir = file.path(getwd(), "recall-evaluation-live")
)
live$eval(view = FALSE)
live$get_samples()[, c("case", "result", "score")]
```

Each case uses its own chat and store. Inspect the linked recall request
and result alongside the answer when interpreting a model’s score.
