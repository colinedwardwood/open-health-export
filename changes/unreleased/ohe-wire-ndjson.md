### ohe.wire/1 NDJSON batches

Local-file export now writes canonical NDJSON: `batch.header`, `sample.quantity` /
`tombstone` records, `batch.footer` with `contentDigest` (`sha256:` over the record
lines). Metric identifiers on the wire are `heart_rate` / `step_count`. JSON and CSV
encodings and the HAE profile are not implemented yet.
