# Make the definition migration a hard cut

Phase 3 removes `GraftMeasure`, `graft_measures()`, `graft_measure()`, per-measure parameter and dimension allowlists, and the singular Receipt definition field without compatibility aliases. Graft is pre-production, and carrying the legacy measure model beside composable definitions would leave two conflicting public contracts for the same governed calculation. Callers migrate directly to `graft_definitions()`, `graft_calculate()`, and the canonical Receipt `definitions` array.
