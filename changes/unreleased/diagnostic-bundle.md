### Bounded manifest-derived diagnostic bundle

Diagnostics now serialize a sorted `ohe.diagnostic/1` JSON document capped at
200 runs and 200 KiB. Bundle fields are selected by a per-sink redaction
manifest; raw run IDs and free-form detail are excluded. The share payload does
not exist until `DiagnosticPreviewGate` records full-content review.
The app reads runs through an independent read-only SQLite connection, checks
integrity first, and skips malformed journal rows. A partial diagnostic names
the degraded subsystem and skipped-row count instead of depending on the
primary state-store path it is diagnosing.
