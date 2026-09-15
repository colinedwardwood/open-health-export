Run volume-gate ExportRuns serially, matching the app's production metric execution,
so the 100 MiB ceiling measures one bounded export instead of four concurrent test
workers.
