### Census accumulates; tombstones maintain the index

`Census.apply` now folds samples into the existing per-(metric, day) row with an
order-independent XOR digest instead of overwriting the page. Tombstones remove
the UUID from `emitted_index` and decrement the census when the UUID is known;
unknown deletions journal `deletion_undatable`. `ReconcileCompare` classifies
identical / countGreater / countSmaller / digestMismatch cells and derives
absence tombstones from the index set-diff. The sweep itself still does not run.
