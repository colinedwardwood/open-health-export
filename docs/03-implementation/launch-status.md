# Launch status

**As of:** 2026-11-25. Tracking issue: #131. Backlog: GitHub Project 6.
Read this first when picking the work up; it says what's done, what's in flight and
what's next. Decisions live in the PRD's decision table (§11.0a) and the ADRs.

## Product

- **Name:** KeepMyMetrics (store), "Keep Metrics" (home screen). Subtitle "Your vitals,
  on your server" (confirmed). Bundle root `com.cewdesign.exporter`. Brand guide:
  `docs/02-design/10-brand.md`.
- **Model (D-08a, D-08b):** free download; Export now and the Control Centre button are
  free to every destination; a one-time US$14.99 unlock adds automatic exports
  (background wakes, observers, catch-up on open, Shortcuts). Family Sharing on.
- **Scope (D-20) and release gates (D-21):** adopted from PM-1 and PM-2.
- **Licence (D-22, ADR-0005):** FSL-1.1-ALv2, receiver Apache-2.0, spec CC0, docs
  CC-BY. Copy says "source-available", never "open source". (Merged, #186.)
- **Platforms:** iPhone only for 1.0; Mac companion in 1.1; no EU storefronts at launch.

## Built (on main)

| Area | Issue | What exists |
|---|---|---|
| Services | #42 | `Sources/AppServices` (Linux-tested); app adapters in `Apps/Exporter-iOS/Services` |
| App shell | #43 | `AppModel`, `AppEnvironment`, four-tab `RootView`, `DeepLinkRouter`; harness deleted (#56) |
| Visual system | #44, #57 | `StatusTone`, `Theme.xcassets` (light and dark), `Styles.swift`; layered `Apps/Icon/AppIcon.icon` |
| First run | #45 | `Apps/Exporter-iOS/Onboarding` |
| Status | #46 | `Apps/Exporter-iOS/Status`, `StatusDashboard`, `UserFacingFailure` |
| Destinations | #47–#49 | Files, HTTPS, Home Assistant webhook, MQTT with discovery; shared test checklist |
| Unlock | #68 | `AutomationGate`, `PurchaseStore` (StoreKit 2, `OHE_STORE_BUILD` archives only) |
| Store listing | #53 | `store/en/` in the brand voice |

## Merged since 2026-10-05

Data tab (#50, #180), History (#51, #181), Settings and About (#52, #182), the FSL
relicense (#186), Swift jobs pinned to `ubuntu-24.04` (#188), and in #191 the harness
deletion with the 600-line and `@State` lint and the release-artifact string scan
(#56), demo mode with plausible values and separate output (#58) and the iCloud Drive
folder warning (#59). Localisation (#54, #192) moved `Sources/` copy to catalog keys
(ADR-0006); the data-flow explainer and scheduling copy are not migrated yet.

After that: #194 (category day reader for Mindful minutes and Sleep, Home Assistant discovery
names, the flaky ledger test, Data save errors, more copy as catalog keys) and #196
(launch and background failures shown on Status, overdue-alarm blind spots, backfill when
a scope widens, DEBUG-gated test hooks and release scan). Open gaps are recorded on #61,
#63, #69 and #74; #60 (Time Sensitive notices) needs an owner decision on permission
prompts and the entitlement. Launch docs (corrected claims, runbooks, changelog draft) are
in PR #195 awaiting owner review.

No product UI remains for OTLP, the anchor-hold banner, diagnostics, backfill or the
Live Activity trigger; their backend code is still there. Decide whether to build
screens for them or remove the code.

GitHub's macOS runners are the bottleneck: run CI for one PR at a time, or jobs queue
for hours and get cancelled (rerun with `gh run rerun <id> --failed`). Text-only PRs
(docs, store copy) can merge on the Linux checks, which include `policycheck`.

## Next engineering work, in order

1. Follow-ups: #172 (audit fold suppression), #60, #74, the gaps on #61/#63/#69, Remove for network destinations, MQTT client certificates, and wiring `HADiscovery.encodeDeviceConfig` (it needs `ProductName.display`).
2. Finish #54: migrate the remaining plain-`String` copy and extend the pseudo-locale tests to every screen.
3. **#67** Host the signed advisory feed at `advisories.cewdesign.com` (owner picks GitHub Pages or Cloudflare Pages).
4. **#55** Manual VoiceOver and Voice Control pass (needs a person), and **#73** real-receiver end-to-end tests.

## Owner actions

- **#21** Counsel: charging, liability, privacy policy and terms, CRA. (FSL already approved.)
- **#22** Trademark clearance and filing for KeepMyMetrics.
- **#23** Paid Apps Agreement, tax and banking; register the App IDs; create the app record and the in-app purchase `com.cewdesign.exporter.unlock` (not for sale until counsel replies); remove EU storefronts; Small Business Program.
- **#20** cewdesign.com: registrar lock, DNSSEC, CAA, auto-renew. Register keepmymetrics.com and .app.
- Move the advisory signing keys to Proton Pass and VeraCrypt, then delete the local copies.

## Conventions that bit us

- **UI tests on CI start from a fresh simulator.** Apple's Health sheet appears and must be answered (`allowHealthSheetIfShown()`). Reproduce locally with a new `simctl create` device; a reused simulator has permission already decided.
- **CI signs the UI-test build ad hoc** (`CODE_SIGN_IDENTITY=-`) so the HealthKit entitlement is present.
- **Accessibility audit:** list footers and `.secondary` text fail contrast (use `SectionFooter` and `Color.secondaryText`); an icon `Label` in a prominent button or a list row can clip; text pushed below the fold at large sizes is suppressed only below `auditFoldBottom` (#172).
- **Copy:** product screens never show `localizedDescription` (policycheck); every new UI literal goes in `Apps/Localizable.xcstrings`; device names come from `DeviceNoun`.
- **Run history persists between UI cases** on a CI shard, so populated-history layouts only appear there; a case cannot assume an empty History (the `OHE_WIPE_ON_LAUNCH` reset went with the harness).
- **Pseudo-locale plurals** render as `#@value@ %#@value@`, not doubled text.
