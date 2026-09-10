Full-history backfill now has an integrity-sealed, inspectable checkpoint and
runs newest-first without touching live anchors. Completion is persisted only
after a chunk commits, so interruption repeats at most one chunk and skips none.
The JSON checkpoint is mirrored in SQLite; disagreement fails closed instead of
silently restarting.

Aggregate-only is the first-run default; raw history is a separate explicit
action. iOS 26 uses a user-initiated continued-processing task for unattended
completion, while iOS 18–25 uses a foreground path that prevents idle sleep and
states the limitation in-product.
