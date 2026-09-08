Add a fork-safe `macos-build` workflow with cancellation and a 15-minute
budget. It runs Darwin package tests, generates the Xcode project, builds the
iOS exporter plus widget against the Simulator SDK, and builds the macOS
companion. HealthKit, Network.framework, App Intents and app-extension code are
therefore compiled on every push and pull request instead of being invisible
to Linux CI.
