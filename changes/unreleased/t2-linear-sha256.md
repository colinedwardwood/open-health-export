Keep ExportRun history SHA-256 linear in payload size so T2 pages do not
re-hash each bounded NDJSON batch quadratically.
