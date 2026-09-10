### Scan shipped release binaries for private test data

The macOS release gate now builds and scans the iOS exporter, its status-widget extension,
and the macOS companion. It rejects debug-only fault seams, private-data logging overrides,
and the health-data canary corpus, which is now excluded from release compilation.
