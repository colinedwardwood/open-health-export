SEC-16: persist destination export scopes in SQLite as one deterministic,
versioned payload per destination. Missing scope remains distinguishable from
an explicitly empty grant, updates replace atomically, destructive wipe clears
all scopes, and migration from the original schema preserves cursors and
journal history.
