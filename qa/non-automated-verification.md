# Non-automated verification index

This is the single release-review index required by QA-36. An entry means that the
claim cannot honestly be completed by CI. It does not mean that a physical run has
occurred. Release evidence must contain no HealthKit values, credentials, destination
hostnames, or other personal data.

| Gate | Non-automated subject | Owner | Required evidence | Automated or field alternative |
|---|---|---|---|---|
| QA-36 / R-71 | Background wake timing and platform delivery caps | Release QA owner on REF-A and REF-B | Five-week, value-free wake diary and published aggregate latency/cap findings | Exercise callback handling with synthetic sources; use value-free field latency distributions |
| QA-36 / R-88 / QA-35 | Multi-week continuity | Release QA owner | Validated `qa/soak/` record covering at least 21 consecutive device days; private reconciliation worksheet; signed redacted result | Pipeline interruption/model tests and field staleness metrics |
| QA-36 / R-87 / QA-34 | Apple Watch and other real-source generation | Release QA owner with qualifying store | Validated `qa/device-pass/` record on named hardware, with at least two years of history and three source classes; no values or source app names in public evidence | Synthetic Watch-shaped fixtures and the community device matrix |
| QA-36 / R-62 / R-63 | Apple's Health permission UI | Device-pass operator | Per-release device-pass section recording requested/denied/limited handling and disclosure ordering | Assert requested type sets and every returned authorization state in app tests |
| QA-36 | Cloud-provider OAuth | Destination owner, if a cloud destination is admitted | Manual pre-release checklist and provider test-account result | Recorded HTTP fixtures and transport contract tests. Dropbox and Google Drive are currently out of scope, so evidence is `not-applicable` |
| QA-36 / SEC-30 | iCloud Drive and backup semantics | Security owner | Manual iCloud/Finder backup and restore result, including the R-33 protocol where applicable | File-write and backup-exclusion attribute tests. The app ships no bespoke iCloud destination |
| R-33 / SEC-30 / SEC-33 | Device-only credentials and excluded storage | Security owner | `qa/encrypted-backup/PROTOCOL.md`: encrypted local backup scan each release and second-device restore each minor release | Keychain attribute tests, backup-exclusion tests, and policy checks |
| QA-36 / QA-25 / R-77 / R-78 | Energy and battery | Performance owner | `qa/energy-protocol.md` measurement on named hardware and value-free field aggregate | Synthetic workload performance tests; no CI battery pass claim |
| R-79 / R-91 | Telemetry wake-budget cost | Performance owner on REF-B | Named-device signpost/MetricKit protocol with p90 and release sign-off | Structural test that OTLP does not run during a wake; synthetic phase-timing tests |
| QA-29 | Community hardware coverage | Community QA owner | Rows in `qa/community-device-matrix/results.csv`; never invent rows | Simulator smoke and fork-safe build checks |
| R-108 / QA-30 | Stranger build from source | Release manager plus non-maintainer | Clean-machine build record for the candidate tag | Fork-safe CI build |
| R-89 / QA-12 | Real Home Assistant versions | Destination owner | Version-pinned integration result against oldest supported and current stable | Schema and local contract tests |
| R-90 / QA-11 | Real MQTT broker behavior | Destination owner | Version-pinned broker integration result, including restart behavior | Codec tests and Darwin loopback transport tests |
| QA-22 | Upstream service canaries | Destination owner | Nightly/release canary status and linked divergence issue when red | Recorded service fixtures; canaries are not required pull-request checks |
| QA-31 | Upgrade, accessibility, localization, and release review | Release manager | Completed release issue checklist with linked, redacted evidence | Automated migration, accessibility audit, pseudo-locale, RTL, and catalogue checks where available |

## Release review

For every row, record one of `pass`, `fail`, `blocked`, or `not-applicable` in the
release issue, plus an owner and evidence reference. `Not-applicable` requires a scope
reason. `Blocked` and `fail` are not passes. Evidence references should be issue URLs,
artifact digests, or private-record identifiers—not raw device exports.

The protocols under `qa/` produce blank templates and validate structure. They do not
attest that a human performed a device action.
