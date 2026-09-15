QA-31 migration evidence is now machine-readable for the first release.
`qa/migrations/v1.json` binds schema v1 to the current schema version, the
`export-core` check, and the existing anchor, journal, destination-scope,
process-exit, backfill, and checkpoint-format tests. Automation verifies that
the manifest's fixture and test names exist and that its target version matches
`SQLiteStateStore.expectedSchemaVersion`.

The programmatic v1 fixture moved from the production `StorageSQLite` target to
`TestSupport`. A store captured from the previous release and an N-1 to N
device upgrade remain mandatory after v1.0.0 exists; the release checklist
already carries the explicit first-release exception.
