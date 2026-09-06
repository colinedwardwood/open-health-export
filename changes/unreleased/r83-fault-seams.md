### Six debug-only fault boundaries

R-83's six stable pipeline locations are now injectable in debug builds: after read, after
transform, after durable enqueue, after destination write before acknowledgement observation,
after acknowledgement before release, and inside cursor persistence. A table-driven SQLite test
proves pre-commit faults roll back, post-commit faults remain replayable, and replay does not
duplicate the local-file result. Release compilation removes the injector API and calls.
