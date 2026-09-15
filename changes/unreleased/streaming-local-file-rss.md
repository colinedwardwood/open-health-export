Local-file delivery and sidecar encodings now stream from payload files instead of
holding NDJSON, JSON, pretty JSON, CSV, and HAE copies at once. That keeps the
ExportRun RSS gate measuring a production-shaped page, not a harness materialisation
bug. The 100 MiB Linux ceiling is unchanged.
