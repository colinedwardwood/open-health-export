### Six debug-only fault boundaries

R-83's six stable pipeline locations are now injectable in debug builds: after read, after
transform, after durable enqueue, after destination write before acknowledgement observation,
after acknowledgement before release, and inside cursor persistence. A table-driven SQLite test
proves pre-commit faults roll back, post-commit faults remain replayable, and replay does not
duplicate the local-file result. Release compilation removes the injector API and calls.
HealthKit database-inaccessible errors are classified as device-locked; the export run records
a `blockedDeviceLocked` journal row without advancing a cursor or creating a batch.
Release CI scans every seam name plus the injector protocol/types and process-exit marker
instead of checking a single representative string.
