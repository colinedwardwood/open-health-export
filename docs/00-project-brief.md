# Project Brief — open-health-exporter

> Shared context for all contributors (human and agent). Read this before producing any
> stage artifact. This brief states the *premise*; it is deliberately light on decisions,
> because the decisions are what each stage is supposed to produce.

## One-line premise

An open-source, Swift-native application for Apple platforms that lets a person export,
automate, and own the health data that Apple Health (HealthKit) holds about them.

## Reference product

[Health Auto Export](https://www.healthyapps.dev/apps/health-auto-export/) by HealthyApps is
the closest commercial equivalent and the de facto benchmark. Its advertised surface:

- Automated exports to REST APIs, MQTT, Home Assistant, Dropbox, Google Drive, iCloud Drive,
  and Calendar
- 150+ health and fitness metrics exported as CSV, JSON, or GPX (workouts, sleep, heart rate,
  medications, ECG)
- A built-in TCP server for direct data reads, plus documentation for custom integrations
- Privacy-first posture: data stays on device, no account, no tracking
- iPhone, iPad, Mac, Apple Watch; a Mac companion for viewing/analysis
- Statistics charts and Home Screen widgets
- An open-source companion server for Grafana visualisation

We are not cloning it. We are building an OSS alternative and should be explicit about where
we intend to be better, where we intend to be at parity, and where we intend to deliberately
do less.

## Intended differentiators (hypotheses, not commitments)

1. **Genuinely open source** — the app itself, not just a companion server. Auditable by the
   people whose health data it moves.
2. **Swift native, modern** — SwiftUI, Swift 6 strict concurrency, Swift Package Manager,
   first-class support across iOS / iPadOS / macOS / watchOS.
3. **Observable by design** — OpenTelemetry tracing plus a mainstream structured logging
   framework, so that a user or self-hoster can actually see why an export failed. This has
   an obvious and unresolved tension with the privacy-first posture; that tension is a
   requirement to resolve, not a detail to gloss over.
4. **Self-hoster friendly** — the people most likely to want this run their own stack.

## Environment and toolchain (verified)

| Item | Version |
|---|---|
| macOS | 26.6.2 (build 25G83) |
| Xcode | 26.6 (build 17F113) |
| Swift | 6.3.3 |
| Repo | `/Users/colin/Code/open-health-exporter`, git initialised, branch `main`, zero commits |

## Delivery process

Four gated stages. Each stage is led by a coordinating product manager, informed by parallel
specialist contributions, and may not close until a deliberately adversarial reviewer has
attempted to sink it and the resulting findings have been dispositioned.

| Stage | Artifact | Location |
|---|---|---|
| 1 | Product Requirements Document | `docs/01-prd/` |
| 2 | System Design | `docs/02-design/` |
| 3 | Implementation | `docs/03-implementation/` + source |
| 4 | Testing / QA | `docs/04-qa/` |

Architecture decisions with long-lived consequences are recorded as ADRs in `docs/adr/`.

## Rules of engagement for contributors

- **Stay in your stage.** During Stage 1 the output is *requirements*: what must be true for
  the product to be worth building, and how we will know. Not schemas, not module layouts,
  not code.
- **Be falsifiable.** "Fast sync" is not a requirement. "A delta export of 10k samples
  completes in under 5s on an iPhone 13" is.
- **Cite or flag.** Anything load-bearing that came from research gets a URL. Anything
  load-bearing that came from your own judgement gets labelled as an assumption.
- **Surface constraints early.** Platform rules that invalidate a desirable requirement are
  the single most valuable thing you can contribute. Say so loudly rather than politely.
- **Disagreement is signal.** Do not soften a finding to fit the premise above. If the
  premise is wrong, say the premise is wrong.
