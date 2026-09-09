Local-file delivery now co-emits canonical JSON, pretty JSON, quantity CSV
plus `_meta.json`, and HAE JSON in a `{batch}.encodings/` folder beside the
NDJSON archive when the batch parses. CSV remains non-convergent; HAE is
skipped when tombstones exist.
