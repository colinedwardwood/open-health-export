The engineering harness is gone (#56). The app shows only the product screens;
there is no Developer screen, and its OTLP, demo-export, traceparent and timing
controls no longer exist. The UI suite drives the Status, Data, Destinations,
History, Settings and first-run screens. `policycheck` now fails a Swift file in
`Apps/Exporter-iOS` over 600 lines or a view with more than 15 `@State`, and the
release-artifact scan fails a shipped harness string.
