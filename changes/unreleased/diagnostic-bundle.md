### Bounded manifest-derived diagnostic bundle

Diagnostics now serialize a sorted `ohe.diagnostic/1` JSON document capped at
200 runs and 200 KiB. Bundle fields are selected by a per-sink redaction
manifest; raw run IDs and free-form detail are excluded. The share payload does
not exist until `DiagnosticPreviewGate` records full-content review.
