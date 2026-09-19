# Retire native graph and compiler APIs

Status: accepted for the pre-production artifact-only release.

Graft is the shared home for persistent artifacts, exact dependency selections,
explicit host decision history, and vocabulary bound to data-dict. Tempest and
Rill remain end-use applications. Commons supplies live analysis.

Remove native stores, schema compilation, graph plans/snapshots, calculation,
managed OKF trees, and graph agent adapters. Consumer contract 3 is a hard cut;
artifact, selection, decision, and vocabulary bytes keep their existing formats.
Tempest must remove native inputs and sidecars together and retain scientific
validation and fresh admission. scans must consume the current Tempest projection.

Earlier compiler and migration ADRs and experiment observations document the
path to this decision. They do not create compatibility requirements. Recovery,
concurrent publication, access enforcement, and erasure remain separate work.
