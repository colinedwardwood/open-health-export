Wire encoding and sidecar generation now stream. The payload is encoded straight to
its file instead of being assembled as `Data`, and the CSV and HAE sidecars are
written from the NDJSON on disk a record at a time rather than rebuilding the page
as records, rows, and a `CanonicalJSON` tree. A full T1 page peaked at 141 MiB
against R-74's 100 MiB ceiling; it now measures about 78 MiB. Both streaming
writers are pinned byte-identical to the in-memory encoders they replace.
