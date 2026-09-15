R-114's demo quickstart budget is now actually measured. The test that enforces it could
never pass: the demo export writes to the local archive folder, `setUp` deletes the
bookmark for it, and the only way to select one in the product is the Files picker, which
XCUITest cannot drive. So the export failed on "no archive folder selected" in
milliseconds, the status line read `Failed: …`, and the case then sat waiting out its full
ten-minute timeout — reporting a timing failure for an export that never started. The
ten-minute claim had never been measured at all.

A DEBUG-only `OHE_SEED_LOCAL_EXPORT_FOLDER` seam seeds a real directory inside the app
container and records a real bookmark for it, so everything past folder selection is the
production path. A folder the app already owns has no security scope to start, so
resolving that bookmark needs an unscoped access that is also DEBUG-only and narrowed to
URLs inside the app container — a genuinely inaccessible picked folder still reports as
inaccessible. R-83 keeps both out of release builds.

Measured: the quickstart completes in about 24 seconds against its ten-minute budget,
writing 154 files across the 48 selectable metrics.

Found only because macOS CI has been too starved to run the UI suite; every recent
`macos-build` run is queued and the last two to finish were cancelled.
