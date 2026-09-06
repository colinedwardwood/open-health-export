### Cross-platform local-file idempotency

Redelivering an existing idempotency key now compares the completed destination with the source
and returns its receipt without replacing the file. Different bytes for the same key fail closed
as an idempotency conflict. This avoids Foundation's destructive replacement edge on Linux.
