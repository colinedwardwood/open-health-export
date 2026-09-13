Coalesce T2 spool writes and count ExportRun receipts in one NDJSON walk so
the fifty-million-record checker spends less time in syscalls and payload scans.
