# Retain artifacts in host-selected PostgreSQL scopes

Status: accepted for the first Rill Reader Memory integration.

Rill already persists hosted state in PostgreSQL. Per-Reader local artifact
directories would require a separate durable volume, backup system, and
cross-store transaction protocol. Use PostgreSQL scopes for this deployment;
retain local stores for single-writer local workflows.

Graft owns the generic object table, immutable bytes and digests, selections,
and decision journals. Each database operation includes the host-selected
scope. Identical content is independently retained within each scope. Rill
owns authenticated Reader identity, Document access, approval, and its private
memory catalog and Reading History. An actor string or scope key authenticates
nothing, and database credentials remain trusted host capabilities.

The host opens a DBI transaction. Graft requires it and holds a PostgreSQL
advisory transaction lock for the scope. Host records and artifacts commit or
roll back together; a returned decision is provisional until commit succeeds.
Fresh workers obtain a new connection and repeat host authorization. Rill
checks active Reader status under a row lock, revalidates session authority,
and passes no Reader selector to model-visible memory tools.

Reader disablement and Archive are distinct from permanent Forget. Neither
PostgreSQL deletion nor transaction rollback constitutes a backup erasure
protocol. Issue #48 remains the rollout gate. Do not serialize store handles,
use scope keys as bearer credentials, or expose raw connections to models.
