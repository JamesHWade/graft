# Continuous intelligence example

This installable example demonstrates a passive scheduled monitor that can
promote material findings into a governed follow-on workflow. The Blue-Sky
profile supplies a playful themed-experience scenario, but none of its domain
objects, labels, or routing choices are added to the public API of either
Graft or Tempest.

The example uses a frozen corpus and provider-free R operations. Its purpose
is to verify workflow, artifact, approval, lineage, and ingestion contracts
deterministically. A model-powered monitor can later replace the scripted
operation without changing those contracts.

## What the example proves

1. A scheduled Tempest workflow reads bounded accepted context from Graft.
2. The workflow produces a Markdown briefing and a structured monitor result.
3. A no-material-change day succeeds without inventing a signal or requesting
   approval.
4. Candidate records enter a separate approval-gated Tempest workflow.
5. Graft remains unchanged while that workflow awaits approval.
6. After approval, the host maps the artifact to record data frames and calls
   `kg_ingest_tempest_records()`.
7. A workflow referral requires a host-stored human promotion bound to the
   referral and is resolved only against the profile's allowlist.
8. The promoted workflow validates cited evidence against the claims used for
   its decision and produces another approval-gated result.
9. The approved decision supersedes the prior active position instead of
   leaving conflicting current decisions.
10. The following briefing retrieves the accepted current decision history.

The host never uses `tempest_artifact_store_graft()`. Tempest artifacts remain
Tempest artifacts; only approved, schema-mapped knowledge records are handed
to Graft.

## Run the complete scenario

From a checkout containing the current development versions of both packages:

```r
devtools::load_all("../tempest")
devtools::load_all(".")
source("inst/examples/continuous-intelligence/run-demo.R")
```

The returned `continuous_intelligence_demo` object contains the three monitor
runs, two knowledge-review runs, the promoted decision run, and final record
counts. All storage is temporary and the run requires no API key or network
connection.

## Layout

- `schema/blue-sky.linkml.yaml` is the application-owned Graft schema.
- `profiles/blue-sky.json` defines audience, sections, scope, and allowed
  workflow referrals.
- `profiles/package-maintainer.json` is a contrasting configuration used to
  check that the host kernel contains no Blue-Sky assumptions.
- `corpus/` contains the accepted baseline and three dated signal bundles.
- `R/host.R` is the domain-neutral reference host.
- `R/blue-sky.R` maps the promoted referral into the application-specific
  decision result and approved Graft records.

## Reconfigure the loop

A different application replaces the profile, schema, corpus or source
adapter, and registered result builder. It retains the same sequence:

```text
observe -> reconcile -> brief -> propose -> route -> review -> learn
```

Scheduling, authenticated connections, authorization, materiality policy,
workflow registration, and approved writes remain host responsibilities.
Schema evolution is intentionally outside this first slice.
