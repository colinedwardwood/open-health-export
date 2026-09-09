A committed `user_version = 1` SQLite fixture migrates through the current
ALTER TABLE path without resetting the HealthKit checkpoint (P14). Checkpoint
format 1 bytes are frozen. Nightly and PR CI now stream corpus NDJSON through
`pipelinecheck` so T1 is not only hashed, it is schema-validated.
