# Launch status

**As of:** 2026-10-05. Tracking issue: #131. Backlog: GitHub Project 6.
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
  CC-BY. Copy says "source-available", never "open source". (Merges with #186.)
- **Platforms:** iPhone only for 1.0; Mac companion in 1.1; no EU storefronts at launch.

## Built (on main)

| Area | Issue | What exists |
|---|---|---|
| Services | #42 | `Sources/AppServices` (Linux-tested); app adapters in `Apps/Exporter-iOS/Services` |
| App shell | #43 | `AppModel`, `AppEnvironment`, four-tab `RootView`, `DeepLinkRouter`; harness is DEBUG-only |
| Visual system | #44, #57 | `StatusTone`, `Theme.xcassets` (light and dark), `Styles.swift`; layered `Apps/Icon/AppIcon.icon` |
| First run | #45 | `Apps/Exporter-iOS/Onboarding` |
| Status | #46 | `Apps/Exporter-iOS/Status`, `StatusDashboard`, `UserFacingFailure` |
| Destinations | #47–#49 | Files, HTTPS, Home Assistant webhook, MQTT with discovery; shared test checklist |
| Unlock | #68 | `AutomationGate`, `PurchaseStore` (StoreKit 2, `OHE_STORE_BUILD` archives only) |
| Store listing | #53 | `store/en/` in the brand voice |

## In flight (PRs merging in order)

1. #180 Data tab (#50)
2. #181 History tab (#51)
3. #182 Settings and About (#52)
4. #186 Relicense to FSL. Its PRD row (D-22) is inserted at the same place as D-20/D-21 from #185, so expect one small conflict in `docs/01-prd/PRD.md` when it's rebased: keep all three rows.

Each needs the full CI run, including the three iOS UI shards. GitHub's macOS
runners are the bottleneck: run CI for one PR at a time, or jobs queue for hours and
get cancelled. Text-only PRs (docs, store copy) can merge on the Linux checks, which
include `policycheck`.

## Next engineering work, in order

1. **#56** Delete `HarnessView`/`HarnessExport` and re-point the UI suite at the product screens (drop `OHE_ROOT=harness`). Then the remaining #42 forwarders go, and #43's UI_TESTING configuration.
2. **#54** Localisation plumbing (all copy through the String Catalog).
3. **#58** Demo mode: plausible values, separate output.
4. **#59** iCloud Drive warning for the Files destination (a footer exists; the issue wants detection).
5. Follow-ups: #168 (category daily totals and reconcile), #177 (Home Assistant discovery names), #178 (flaky ledger test), #172 (audit fold suppression), Remove for network destinations, MQTT client certificates.
6. **#67** Host the signed advisory feed at `advisories.cewdesign.com` (owner picks GitHub Pages or Cloudflare Pages).
7. **#55** Manual VoiceOver and Voice Control pass (needs a person), and **#73** real-receiver end-to-end tests.

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
