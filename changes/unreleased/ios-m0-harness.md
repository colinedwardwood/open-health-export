### iOS M0 harness

XcodeGen `project.yml` produces `OpenHealthExporter.xcodeproj` (gitignored). The app requests
Health read access only after the locked-device / best-effort disclosure, then can run
`HealthKitThroughput.measure` on-device for R-70. A third control runs `ExportRun` +
`LocalFileSink` into Application Support (Class C until first unlock) so the write-ahead
engine can be exercised on a phone before HTTPS exists.
