# Build, Release and Governance Machinery — Stage 2

**Role:** Release & Build Engineer
**Stage:** 2 of 4 (System Design)
**Status:** Draft for PM synthesis and adversarial review
**Date:** 2026-09-03
**Owns:** R-100, R-101, R-105a, R-105b, R-106, R-107, R-108, R-109, R-110, R-111, R-112, R-113,
R-114, R-115, R-116; constraints C-08 through C-13
**Coordinates with:** QA lead (`contributions/08-qa-lead.md`) on CI topology and the synthetic
corpus; governance lead (`contributions/09-oss-governance.md`) on the artifact manifest and
dependency policy; ADR-0001 on the licence and the §7 permission

> **Not legal advice.** Sections marked **[R-112]** identify text or analysis that should be
> reviewed by the paid opinion D-12 funds before it is published. Everything else is
> engineering judgement.
>
> **Currency.** Costs and policy checked 3 September 2026. Two items are dated and move:
> CRA Article 14 reporting begins **11 September 2026** (8 days from today), and the Commission
> FOSS guidance the governance lead relied on is a **draft** (C(2026) 5252).

---

## Executive summary

Eight decisions, and the reasoning for each is in the section named after it.

1. **One monorepo, one SPM package, many targets — plus a second small repository for the
   Home Assistant integration.** The Linux constraint (R-80) is enforced by the target graph
   and a required Linux build, not by review discipline: `HealthKitAdapter` is a leaf that
   nothing in core depends on, so the moment a core target imports it the Linux job fails. The
   HA integration needs its own repo because HACS's model is one repository per integration
   with GitHub *releases* driving the version, which is structurally incompatible with a
   monorepo whose releases are iOS app releases.

2. **Exactly one file in the tree contains the brand.** Bundle identifiers, module names,
   scheme names, the repo name, the Home Assistant `domain`, the MQTT topic prefix and the tag
   format are all functional and unbranded. A `rename-drill` CI job substitutes a nonsense
   brand and asserts a clean build. D-06 stays open at zero ongoing cost.

3. **The release path is split three ways on a single principle: put each credential where it
   is least exposed.** Xcode Cloud archives, signs and uploads (Apple holds the signing
   identity; we store nothing). GitHub Actions produces every artifact that carries a
   transparency claim (its definition and logs are public, which is the point). A self-hosted
   Mac notarises the Developer ID build and runs the device gate (the Team API key that
   `notarytool` requires never touches hosted CI).

4. **Two maintainers both ship releases via cloud-managed distribution certificates**, not a
   shared `.p12`. The binding constraint is a role detail: *Access to Cloud Managed Developer
   ID Certificate* is grantable only by the Account Holder and only to **Admins**. So the
   second maintainer must hold Admin, not App Manager, or R-105b is unsatisfiable for the Mac
   target.

5. **Three independent version streams** — app, wire spec, HA integration — because R-12
   freezes the spec independently of the app. A `spec-freeze` CI gate diffs frozen spec
   directories against the tag that froze them and fails on any change.

6. **We claim auditable source and verifiable provenance. We do not claim a reproducible
   binary, and we say why.** C-09 is real: Apple re-signs and FairPlay-encrypts App Store
   binaries. What we ship instead is a pinned toolchain, a pinned dependency graph, Sigstore-
   backed build attestations on every artifact we produce ourselves, and a per-release
   *stranger test* executed both by CI and by a named human. R-84's byte-determinism is about
   *export output*, not build output; conflating the two would be over-claiming.

7. **The compliance gate is mostly a program.** R-110 and R-113 are automatable and become
   build failures. R-109 and R-111 are not automatable and become named, evidenced sign-offs in
   a release issue that the release workflow reads before it will publish. The unlock for R-113
   is that App Store metadata lives in the repo, because copy CI cannot see cannot be checked.

8. **AGPL-3.0 inverts part of the inherited dependency policy, and the correction matters.**
   Copyleft dependencies are now *licence*-compatible with our outbound licence but are still
   effectively denylisted, because a third-party GPL/AGPL rightsholder has not granted a §7
   app-store permission — which reintroduces the exact veto D-02 was built to close, from a
   party we cannot ask. The shipped-code allowlist stays permissive-only.

The single largest risk I own is **[R-50 versus D-04]**: if the MQTT client we admit depends
transitively on `swift-log`, R-50's prohibition is violated by a dependency, not by us. That
needs a product answer, not an engineering workaround.

---

## Repository and package layout

### Topology

One public monorepo, `open-health-exporter` (the descriptive name; see *Rename survivability*).
One root `Package.swift` with `swift-tools-version: 6.3`. A **generated** Xcode project for the
app shells only.

```
open-health-exporter/
  Package.swift                     # single package, many targets, one Package.resolved
  Package.resolved                  # committed
  .swift-version                    # 6.3.3   (swiftly, Linux/core path)
  .xcode-version                    # 26.6 + exact build number (asserted at build start)
  project.yml                       # generator input; the ONLY place target/scheme names live
  Brand.xcconfig                    # the ONLY place the brand lives
  Sources/
    ExportCore/                     # Linux. Correctness engine, journal, anchors, reconciliation
    ExportWireFormat/               # Linux. Codecs + schema. CC0-1.0 spec lives beside it
    ExportDestinations/             # Linux. File, HTTPS + request template, MQTT, HAE profile
    ExportPersistence/              # Linux. Durable journal, egress ledger, checkpoints
    ExportPolicy/                   # Linux. Redaction allowlist, unit canonicalisation, catalogue
    HealthKitAdapter/               # iOS/iPadOS ONLY. The one place `import HealthKit` appears
    CompanionReceiverKit/           # macOS. Receive-and-write; transport behind a seam
    AppShared/                      # SwiftUI shared by the iOS app, the widget and the Mac app
    ExportTestKit/                  # test-only: fake source, six fault seams, fixture loader
    DemoData/                       # release-safe: decoder for a CC0 data bundle. No seams.
  Tools/
    corpusgen/                      # Linux executable. THE generator (R-82 + R-114)
    policycheck/                    # Linux executable. Compliance, spec-freeze, rename, licences
    releasekit/                     # Linux executable. Changelog assembly, BUILDINFO, SBOM glue
  Apps/
    Exporter-iOS/                   # shell: entitlements, Info.plist, assets, App Intents
    Exporter-macOS/                 # shell: companion
    StatusWidget/                   # shell: widget extension
  spec/
    v1.0.0/                         # FROZEN. schema + fixtures. CC0-1.0
    v1.1.0/                         # in progress
    compatibility.json              # which app versions emit which spec versions
  receiver/                         # R-115: compose.yaml + reference receiver + dashboard JSON
  store/<locale>/                   # App Store metadata as text files (see the compliance gate)
  compliance/                       # disclaimer.txt, denylist.txt, allowlist.txt
  dependencies/                     # policy.md, licences.lock, one file per dependency
  changes/unreleased/               # changelog fragments
  fixtures/FIX-catalogue.md         # QA owns the contents; CI enforces one test per ID
```

Separate repository, `open-health-exporter-hass`, containing only the HA integration. Rationale
and sync mechanism under *Distribution and channel artifacts*.

### Why a single package rather than several

Several packages would let us express "core cannot see HealthKit" as a package boundary, which
reads well. It also gives us N `Package.resolved` files to keep consistent, N places for a
dependency version to drift, and a resolution graph that Xcode and `swift build` disagree
about. A single package with a strict target graph gives the same guarantee — SPM will not let
a target use a symbol from a target it has not declared a dependency on — with one lockfile.

The library products declared in `products:` are the external contract: `ExportCore`,
`ExportWireFormat`, `ExportDestinations`. `HealthKitAdapter` is deliberately **not** a product.
Nothing outside this repo can link it, and inside the repo only the iOS app shell does.

### How the Linux constraint is enforced structurally

R-80 says the whole export pipeline runs with HealthKit not linked, and QA-01 says this is the
single most important thing Stage 2 must honour. Four mechanisms, in decreasing order of how
hard they are to defeat:

1. **The target graph.** `HealthKitAdapter` depends on `ExportCore`; the arrow never points the
   other way. A developer who adds `.target(name: "HealthKitAdapter")` to `ExportCore`'s
   dependencies has written a dependency cycle *and* broken Linux. Both fail immediately, at
   build time, on the cheapest runner.

2. **A required Linux check from the first commit.** `swift build --target ExportCore` plus the
   full L1–L4 suite on `ubuntu-latest` with the pinned swift.org 6.3.3 toolchain via `swiftly`.
   This is a required status check on `main`, it needs no secrets, and it passes on fork PRs
   (R-85, QA-28). Linux is $0.006/min if we ever go private and free while public [5], so this
   is also the tier that carries the majority of the suite.

3. **A legible lint, so the failure is diagnosable.** `policycheck imports` asserts that
   `import HealthKit`, `import UIKit`, `import SwiftUI`, `import WidgetKit`, `import Network`
   and `import CoreLocation` appear only under an allowlist of directories. Without this, the
   first violation surfaces as four hundred lines of "cannot find type 'HKSample' in scope" and
   a contributor concludes the Linux job is broken rather than that they broke it.

4. **A dependency-admission rule.** Any new runtime dependency must build on Linux, or be
   confined to a target the Linux job does not build. This is in the dependency policy because
   it is the realistic way mechanism 2 gets defeated: not by someone importing HealthKit, but
   by someone adding a Darwin-only package to `ExportDestinations`.

Two consequences worth stating because Stage 3 will otherwise rediscover them painfully:

- **`Foundation` is not the same library on Linux.** `swift-corelibs-foundation` differs in
  `Date` formatting, `URLSession` behaviour, `FileManager` semantics and `Locale` availability.
  R-81's injected clock/calendar/locale (QA-03) is what makes this survivable, and the Linux
  job is what makes divergence visible. Design core code against a narrow, explicitly
  enumerated Foundation surface and put the rest behind the injected interfaces of QA-C4.
- **Swift Concurrency and `Sendable` diagnostics differ subtly between the Xcode toolchain and
  the swift.org toolchain of nominally the same version** — they are always distinct builds
  [45]. Warnings-as-errors on both is the only way to keep the two green simultaneously, and it
  is cheaper to adopt at commit one than at commit five hundred.

### The generated Xcode project

`project.yml` is the source of truth; the `.xcodeproj` is generated and gitignored. XcodeGen
(MIT, single YAML, ~200 reviewable lines) is sufficient for three shells; Tuist (MIT) is the
answer if the shell count grows or we need per-module caching [53]. Either is build-time-only
tooling that we do not convey, so it sits in the dependency policy's build-time carve-out.

Reasons this is not a preference:

- A checked-in `.xcodeproj` is a merge-conflict generator and is unreviewable, which is a
  governance problem for a project whose proposition is auditability.
- The rename drill needs target and scheme names to be data, not XML.
- Reviewers can see the whole build configuration in one file, which is what "auditable" means
  in practice.

**The gotcha to design around now:** Xcode Cloud builds a scheme from a cloned repository. With
a generated project there is nothing to build until the generator has run. Xcode Cloud's
documented extension point is `ci_scripts/ci_post_clone.sh` [54], which installs the generator
and runs it. That script must be the *same* entry point Actions and a laptop use, or the three
environments diverge silently — which is the failure mode that makes people distrust CI.

### Coordination boundary with the QA lead

Restated so neither of us builds the other's thing:

| Artifact | QA lead owns | I own |
|---|---|---|
| Synthetic corpus | The FIX-* edge-case catalogue, the statistical model, tier definitions (QA-04/05) | `Tools/corpusgen` as a shipped, Linux-buildable, seed-reproducible executable; its CC0 licensing; its attestation; the demo bundle it emits for R-114 |
| CI tiers | What runs at T0–T3 and what gates a change (QA-27) | The release path specifically: signing, packaging, provenance, distribution, and the compliance gate |
| Test doubles | The scriptable HTTP double, the Mosquitto and HA contract tests (QA-10/11/12) | The reference receiver (R-115), which is the *published* artifact and validates against the same schema |
| Release gate | The QA half of the checklist (QA-31): device pass, soak, canaries, energy, a11y, perf | The release issue template that carries both halves, and the workflow that refuses to publish without it |

There is one generator, one HTTP schema, and one release checklist. Where our lists overlap,
his rows are referenced from mine, not copied.

---

## Rename survivability (D-06 is open)

D-06 defers the name pending a formal clearance search, and RK-9 prices a late rename as
medium-high impact. The design goal is that a rename after first release costs a day, not a
quarter.

### The rule

**Exactly one file contains the brand: `Brand.xcconfig`.** Everything user-visible derives from
it; nothing structural references it.

```
// Brand.xcconfig  — the only branded file in the tree
BRAND_DISPLAY_NAME = Tributary          // pending D-06 clearance
BRAND_SLUG         = tributary          // release asset filenames only
INFOPLIST_KEY_CFBundleDisplayName = $(BRAND_DISPLAY_NAME)
PRODUCT_NAME       = $(BRAND_DISPLAY_NAME)
```

Plus a `Brand/` asset catalog (icon, marketing assets) and a `Brand.strings` for the localised
display name. Three files, all leaves.

### What must never contain the brand, and why each is expensive

| Identifier | Value | Why it is a one-way door |
|---|---|---|
| Bundle identifier | `<entity-reverse-dns>.healthexport`, `.healthexport.companion`, `.healthexport.widget` | Fixed at first build upload; the App Store Connect app record is bound to it permanently |
| Swift module names | `ExportCore`, `ExportWireFormat`, … | A module rename is source-breaking for every fork and every third party who imported a product |
| Repository name | `open-health-exporter` | Rename breaks `Package.swift` URLs, the `hacs/default` entry, dashboard links and every inbound link; GitHub's redirect is best-effort, not a contract |
| Home Assistant `domain` | `health_export` | Keys config entries, entity IDs and the `home-assistant/brands` registration. Changing it invalidates every user's configuration and needs a migration |
| Xcode target and scheme names | `Exporter-iOS`, `StatusWidget` | Referenced by Xcode Cloud workflows, `xcodebuild` invocations and every CI script |
| Tags | `v1.4.2`, `spec/v1.1.0`, `ha/v0.3.0` | Immutable by policy; a branded tag scheme is unfixable retroactively |
| Wire format `producer` field | A stable machine identifier, declared *informational* in the spec and explicitly **not** a matching or routing key | Otherwise a rename is a wire-format break, which R-12 says the app cannot cause |
| MQTT topic prefix, HTTP `User-Agent` | Read from one constant, defaulting to the unbranded slug and user-overridable | Users automate against topics; a rename that reorganises their broker is a support event |
| Grafana dashboard `uid`, datasource variable names | Functional | The catalogue entry and every import-by-uid depend on it |

### What is cheap to rename, and is therefore where the brand may live

- The **App Store display name** is a version-level localizable property; it changes with a new
  version submission and the app record — including accumulated ratings and reviews — survives
  [1]. This is the single most important fact for D-06: the store listing is the *cheapest*
  branded surface, not the most expensive one. The expensive surfaces are the ones above, and
  we keep all of them unbranded.
- README title, landing page, in-app display name, release asset filenames, HACS `name`,
  dashboard title and description.

### The rename drill

A CI job that makes the property testable rather than aspirational:

1. Overwrite `Brand.xcconfig` with `BRAND_DISPLAY_NAME = Zzyzx`, `BRAND_SLUG = zzyzx`.
2. Regenerate the project, build every target, run the full suite. Linux core on every PR;
   full app build nightly and on release tags (macOS minutes are the scarce resource, and
   macOS jobs cap at five concurrent [5]).
3. `policycheck brand` greps the tree case-insensitively for the real brand string and fails on
   any match outside `Brand.xcconfig`, `Brand.strings`, `Brand/`, `store/`, `docs/`, `README.md`
   and `CHANGELOG.md`. Historical changelog and docs entries are legitimately branded; source,
   configuration, schemas and workflow files are not.

Acceptance: the drill is green from the first commit that has a brand. Residual risk after the
drill passes: the `home-assistant/brands` registration and the Grafana catalogue entry are held
in external systems keyed on the unbranded domain and uid respectively, so a rename touches
their *metadata* but not their identity. That is the design working.

---

## Build and signing

### Signing identities under organisation enrolment (D-03)

D-03 resolves C-10 by enrolling the owner's existing legal entity with its D-U-N-S number [52].
That makes shared signing identities possible, which is the whole basis of R-105b. The inventory:

| Identity | Purpose | Who can create | Where the private key lives |
|---|---|---|---|
| Apple Distribution (App Store and Ad Hoc) | iOS/iPadOS App Store submissions | Account Holder or Admin | **Apple**, if cloud-managed. Nobody exports a `.p12` |
| Developer ID Application | Mac companion, notarised, outside the Mac App Store | Account Holder or Admin | Apple, if cloud-managed |
| Developer ID Installer | Only if we ship a `.pkg` rather than a DMG | Account Holder or Admin | Apple, if cloud-managed |
| Apple Development | Per-machine, per-maintainer, disposable | Any developer | The maintainer's login keychain |

**Cloud-managed distribution certificates are the mechanism that makes two maintainers
possible without sharing key material.** With automatic signing, Xcode requests a
cloud-managed certificate whose private key Apple holds; the maintainer signs without ever
possessing an exportable key. Access is granted per user in App Store Connect → Users and
Access → *Access to Certificates, Identifiers & Profiles*, **plus** its child checkbox *Access
to Cloud Managed Distribution Certificate* — both are required, and the failure mode when only
the parent is ticked is an opaque "you haven't been given access to cloud-managed distribution
certificates" at archive time [13].

**The constraint that decides R-105b for the Mac target.** *Access to Cloud Managed Developer
ID Certificate* is a separate grant, it is modifiable **only by the Account Holder**, and per
Apple Developer Support it can be granted **only to users with the Admin role** — an Account
Holder cannot grant it to a Developer or App Manager [14, secondary; verify in App Store
Connect before relying on it]. Therefore:

> The second maintainer must hold **Admin**, not App Manager, if they are to sign or notarise
> the Mac companion. This is a role decision, it is invisible until it bites, and it belongs in
> `MAINTAINERS.md` as an onboarding step rather than being discovered on a release day.

Proposed role assignment:

- **Maintainer A — Account Holder.** The entity's authorised signatory. Not casually
  transferable; transfer is an Apple Developer Support process, which `CONTINUITY.md` documents.
- **Maintainer B — Admin**, with both certificate-access grants and the Developer ID grant.
- **CI — no user account.** It authenticates with an API key (below), never with an Apple ID.

Two scheduled hygiene jobs, because signing failures are always discovered at the worst moment:

1. **Certificate expiry watch.** A weekly job queries the App Store Connect API for
   certificate `expirationDate` and opens an issue at T-60 days, escalating at T-14.
   Distribution certificates run about three years; a lapse during a maintainer's absence is a
   silent release blocker and, for a health app with a security advisory channel, a real one.
2. **Role drift check.** Quarterly, a maintainer confirms the Users and Access grants still
   match `MAINTAINERS.md`. Apple occasionally resets these; there is no webhook.

### App Store Connect API keys

Two key types, and the differences are load-bearing rather than trivia [8, 9]:

| | Team key | Individual key |
|---|---|---|
| Created by | Account Holder or Admin | Any user with the permission; one active key per user |
| Scope | All apps in the account; **cannot be scoped per app** | The associated user's apps and roles |
| Provisioning endpoints | Yes | **No** |
| `notarytool` | Yes | **No** |
| Sales & Finance | Per role | **No** |

Consequences for the design:

- **Notarisation requires a Team key** (or an Apple ID with an app-specific password, or a
  stored `notarytool` keychain profile) [8, 11]. That is the reason notarisation runs on the
  self-hosted Mac with a `store-credentials` keychain profile rather than in hosted CI: the
  credential that hosted CI would need is the broadest one we have.
- **Team keys are account-wide.** With one product in the account this is harmless. It is a
  standing reason not to add unrelated apps to this Apple account, and it belongs in
  `CONTINUITY.md` so a future maintainer does not casually do so.
- Each maintainer holds an **Individual key** for their own local automation. Nobody shares one.
- Key rotation: generate the replacement, update the secret, revoke the old one. Revocation is
  irreversible and revoked keys remain visible for thirty days in App Store Connect [9]. A
  commonly-cited limit of two active team keys [3, secondary] is exactly enough for
  zero-downtime rotation; confirm the current limit before writing the runbook.

### How two maintainers both ship releases (R-105a, R-105b)

**R-105a — a source release, by both.** No Apple credential is involved: a signed annotated
tag, a GitHub release, the provenance bundle, and the changelog. Verification is a
`RELEASE-HISTORY.md` table naming the releasing maintainer per release, reviewed at each
release. Cheap, and it should happen early — the second maintainer's first act after onboarding
is cutting a source release, not reading documentation about cutting one.

**R-105b — an App Store release, by both.** Four preconditions, all of which are configuration
we can complete before either release:

1. Both hold a role that can create a version and submit: Account Holder, Admin, App Manager or
   Marketing can create a new version [1]. Admin covers it and is required anyway for the Mac
   target.
2. Both hold *Access to Certificates, Identifiers & Profiles* and *Access to Cloud Managed
   Distribution Certificate* [13].
3. Both have completed the release checklist end to end, including the parts that are not
   automatable.
4. Both appear in App Store Connect's version history as the submitter of at least one version.

The mechanism: **CI archives, signs and uploads; a human submits.** Submission is deliberately
manual because it is where the non-automatable compliance sign-offs (R-109, R-111) are
attested, and because App Review is not an API contract. So "both have shipped" means both have
driven the whole checklist and pressed submit. Schedule it: the second maintainer owns the first
`x.y.0` release after onboarding, with the first maintainer acting only as reviewer. Recorded as
an onboarding item in `MAINTAINERS.md` with a target date, because D-10 is open and an
unscheduled obligation on a person who does not yet exist is not a plan.

### CI secrets without leaking them

Four principles, in priority order.

**1. Fork PRs never see a secret.** No `pull_request_target` anywhere — a `policycheck
workflows` rule asserts its absence, because it is the standard way this guarantee is lost.
Credentialed jobs trigger only on `push: tags: ['v*']` and `workflow_dispatch`, and are bound
to a GitHub Environment with required reviewers. This is QA-28 and R-85, and it is
non-negotiable: a self-hosted Mac holding a notarisation credential and a real health store
must never execute code from a fork.

**2. Prefer having no long-lived secret at all.** Ranked:

| Approach | Secrets we hold | Verdict |
|---|---|---|
| Xcode Cloud for archive/sign/upload | **None.** Apple holds the identity and the ASC connection | **Adopt for the App Store path** |
| Actions + cloud-managed signing via an ASC Team key | One `.p8`. Revocable, and not a signing private key | Fallback, and used for read-only ASC queries |
| Actions + `.p12` and profiles in secrets (fastlane `match` shape) | Two, one of which is an exportable distribution private key | **Reject** unless forced |
| Self-hosted Mac + `notarytool` keychain profile | One credential, on a machine we physically control, behind a protected environment | **Adopt for notarisation** |

**3. If a `.p8` must live in Actions**, then: Environment secret in a `release` environment with
required reviewers; imported into a temporary keychain created and destroyed within the job;
never echoed; `ACTIONS_STEP_DEBUG` prohibited on credentialed workflows by policy check; push
protection and `gitleaks` on every push; and a post-job log scan for the key ID as a canary.

**4. State what is not available so nobody spends a week on it.** There is no OIDC federation
between GitHub Actions and App Store Connect. Keyless authentication to Apple does not exist;
the choice is between a stored key and Xcode Cloud's managed connection. That asymmetry is the
main technical argument for the split release path.

### Notarisation and the Mac companion

The companion is a receiver, not a HealthKit reader (PC-1), and it accepts health data over the
local network. Two possible channels, and it is a genuine decision:

**Mac App Store.** Apple Distribution certificate; **no notarisation needed**, because App Store
submission already includes equivalent checks [10]. Costs: a second app record, a second App
Review surface on the critical path, App Sandbox, and the sandbox interaction with "write
forever to a folder the user picked" (security-scoped bookmarks) which the iOS document-picker
design does not need.

**Developer ID plus notarisation**, distributed as a signed, notarised, stapled DMG from GitHub
Releases. Requires a Developer ID Application certificate, hardened runtime, a secure
timestamp, `xcrun notarytool submit --wait`, then `xcrun stapler staple` [10, 11, 12].

**Recommendation: Developer ID and notarisation for v1.** Reasons: it keeps the Mac companion
off the iOS launch's App Review critical path; it avoids the sandbox/bookmark work during the
period §7.1 says we are already 87 EW over budget; and the artifact shape matches what
build-from-source users get, which is coherent with R-108. The counter-argument is honest and
should be recorded: a downloaded DMG is a new trust surface for an OSS audience, and
notarisation is therefore mandatory rather than optional — an unnotarised build produces
Gatekeeper messaging that will be read as "this project ships malware".

Mechanics and one concrete de-risking item:

- Hardened runtime with the **minimum** entitlement set. No `allow-unsigned-executable-memory`,
  no JIT, no disabled library validation. The companion needs the network-server entitlement
  and a local-network usage description and little else. Any entitlement addition is a security
  review trigger, recorded as an ADR consequence.
- `notarytool` authenticates with a Team key or a stored keychain profile [11]. Individual keys
  cannot notarise [8].
- **First notarisation from a newly enrolled team can sit In Progress for days** while Apple
  performs account-level analysis. Do a throwaway notarisation of a hello-world binary within
  the first month of the entity's enrolment, long before it is on a release path. This is the
  cheapest de-risking action in this document.

### Xcode Cloud versus GitHub Actions versus self-hosted, for the release path

Costs, current and cited.

**GitHub Actions.** Standard GitHub-hosted runners, macOS included, are free and unmetered for
public repositories [5, 6]. Larger runners are always billed even on public repositories [5, 7].
Private-repo rates after the 1 January 2026 repricing: macOS 3–4 core `$0.062/min`, Linux 2-core
x64 `$0.006/min`, Linux arm64 `$0.005/min`; included minutes 2,000/month on Free and 3,000 on
Pro/Team, with a 10× multiplier on macOS [5, 7]. A `$0.002/min` Actions cloud platform charge
applies from 2026 across hosted and self-hosted runners but **explicitly not to public
repositories** [6].

> **Correction to the QA lead's CI research.** He recorded the self-hosted platform charge as
> "postponed, treat future pricing as uncertain". GitHub's own page dates it to **1 March 2026**
> and states that standard hosted and self-hosted usage on public repositories remains free [6].
> So self-hosted is free for us — but only while the repository is public. That makes "the
> repository is permanently public" a **release-engineering** dependency, not merely a CI-cost
> one: it also determines whether artifact attestations are signed by the Sigstore public-good
> instance, which is what lets an outsider verify them without trusting our tenant [22].

**Xcode Cloud.** 25 compute hours per month included with the $99/year Apple Developer Program
membership; then 100 h at US$49.99/mo, 250 h at US$99.99/mo, 1,000 h at US$399.99/mo and
10,000 h at US$3,999.99/mo [3, 4]. Workflows can be configured by the Account Holder, an Admin
or an App Manager [4].

**Self-hosted.** One Apple-silicon Mac mini with an attached iPhone and Watch: hardware capex
plus power; free minutes on a public repository [5, 6]; subject absolutely to the fork-PR
prohibition.

Assessment against what the *release* path actually needs:

| Criterion | GitHub Actions | Xcode Cloud | Self-hosted Mac |
|---|---|---|---|
| Signing credential we must store | A `.p8`, or worse a `.p12` | **None** | A keychain profile, on hardware we hold |
| Upload to App Store Connect / TestFlight | Via key + `altool` successor tooling | **Native** | Via key |
| Notarisation (`notarytool`, Team key) | Possible, but needs the broadest key in hosted CI | Not its job | **Best fit** |
| Fork-PR safety | Excellent with `push`/`dispatch` triggers | N/A (not PR-driven for releases) | Only with a protected environment |
| Public auditability of the pipeline | **Workflow files and logs are public** | Workflow partly in Apple's UI; logs behind an Apple login | Logs are ours; runner is opaque to outsiders |
| Device tests, real HealthKit store | Impossible | Impossible | **Only option** |
| Cost at our volume | $0 | $0 (25 h ≈ 35–70 release archives/month at 20–40 min each) | Capex + power |
| Bus factor | Any maintainer can read and rerun | Needs an ASC role | One machine, one location |

**Recommendation — split on the principle "each credential where it is least exposed", and make
every step runnable from a laptop.**

1. **Xcode Cloud owns archive → sign → upload → TestFlight distribution.** It is the only option
   where we store no signing credential, it is paid for by a membership we must buy anyway, and
   25 hours per month is comfortable for a release-only workload.
2. **GitHub Actions owns everything that carries a transparency claim**: the Linux core build and
   tests, the source tarball, the SBOM, the build-provenance attestations, the spec and fixtures
   bundle, the reference receiver image, the generated release notes, HACS and hassfest
   validation, and every compliance gate. Reason: our provenance claim is only worth something if
   the pipeline that made it is publicly readable and its logs publicly inspectable. Xcode Cloud
   cannot carry that claim, so it must not be the origin of the artifacts that assert it.
3. **The self-hosted Mac owns notarisation, the device gate (QA's L6), and the pre-release
   performance baselines.** The Team key stays on hardware we control.

The honest downside is three systems. Two mitigations, and they are the actual design:

- **All logic lives in `Tools/` and in `scripts/release/*.sh`.** Actions, Xcode Cloud
  (`ci_post_clone.sh` and `ci_pre_xcodebuild.sh` [54]) and a laptop invoke the same scripts with
  the same arguments. Nothing is expressed only in a CI vendor's YAML or UI.
- **The release runbook must be executable from a laptop with no CI at all.** This is the
  bus-factor requirement from R-106, and it is also what keeps the three systems from drifting:
  if the laptop path is exercised (once per release, by the non-releasing maintainer, as part of
  the R-108 stranger test), the scripts cannot rot.

**Reassessment triggers**, so this is a decision and not a permanent assumption: Xcode Cloud's
included hours falling below our release volume; GitHub's public-repository exemption changing;
the repository going private; or the release archive exceeding ~40 minutes, at which point the
25-hour allowance starts to bind.

---

## Release engineering

### Versioning policy — three independent streams

R-12 requires the wire format to be a versioned specification with its own stability commitment,
independent of the app's release cycle. That means one semver stream is wrong. Three:

| Stream | Scheme | Tag | The public API it governs | MAJOR bump means |
|---|---|---|---|---|
| **App** | SemVer 2.0.0 [51] → `CFBundleShortVersionString` | `v1.4.2` | User-visible behaviour, the destination configuration format, the persisted-state format | A capability is removed, or a state migration is not backward-compatible |
| **Wire spec** | SemVer 2.0.0, independent | `spec/v1.1.0` | Field names, types and semantics; aggregation semantics per metric (R-07); idempotency-key derivation (R-02, R-03) | A field is removed or retyped; aggregation or key derivation changes meaning |
| **HA integration** | SemVer 2.0.0 → `manifest.json` `version` | `ha/v0.3.0` in the mono; `v0.3.0` release in the HA repo | Entity IDs, `unit_of_measurement`, `device_class`, `state_class`, config-entry schema | An entity is renamed, or a config entry is invalidated |

Five rules that make the relationship precise rather than gestural:

1. **Every app release declares the spec versions it can emit and the one it emits by default**,
   in `spec/compatibility.json` and in the README's support matrix. This is the artifact a
   receiver author reads.
2. **The streams do not imply each other.** An app MAJOR bump does not force a spec MAJOR bump,
   and a spec MAJOR bump does not force an app MAJOR bump — the app can emit two spec versions
   during a transition. That is the entire content of R-12 and it should be stated in
   `VERSIONING.md` in exactly these words, because the default engineering instinct is to couple
   them.
3. **A frozen spec version is immutable.** `policycheck spec-freeze` diffs `spec/vX.Y.Z/**`
   against the commit that tagged its freeze and fails on any change, including whitespace. New
   behaviour goes in a new directory. Within a MINOR, changes must be additive and the fixtures
   from the previous MINOR must still validate. This is the CI enforcement R-12's acceptance
   criterion asks for.
4. **Build numbers are monotonic and never reused.** `CFBundleVersion` = CI run number or commit
   count. Apple rejects duplicates, and the roll-forward path below depends on there always
   being a higher number available.
5. **HACS reads the HA repository's latest GitHub *release* tag as the remote version**, and a
   plain tag is not enough — it must be a full release [17]. So the HA stream's tags and its
   `manifest.json` `version` must agree, and that agreement is a CI check in the HA repo.

### Changelog policy

Keep a Changelog 1.1.0 format [50], `CHANGELOG.md` assembled by `Tools/releasekit` from
fragment files in `changes/unreleased/`. Fragments rather than direct edits, because a shared
`CHANGELOG.md` conflicts on every concurrent PR and the resulting friction is how changelog
discipline dies. Fragment presence is a required check on any PR touching `Sources/`, with a
`skip-changelog` label as the escape hatch — and the label's use is auditable, which is the
point of using a label rather than a convention.

Three sections that are unusual and that this product specifically requires:

- **Wire format** — every change, with the spec version it lands in. Self-hosters build against
  this; MKT's P3 persona abandons us when the wire format churns.
- **Correctness and data handling** — anything touching anchors, reconciliation, tombstones or
  the R-09 eviction path gets a plain-language user-facing paragraph. In a product whose entire
  wedge is telling the user the truth about what it did, shipping a silent correctness fix is a
  positioning failure, not just a documentation gap.
- **Supply chain** — dependency added, removed, upgraded across a major, or relicensed (OSS-19).

App Store release notes are *generated from* the changelog by `releasekit`, then hand-trimmed,
and the result is **committed under `store/<locale>/whats-new.txt`** before submission. That is
what makes the R-113 denylist check possible over store copy.

### Release checklist

A GitHub issue template (`.github/ISSUE_TEMPLATE/release.yml`) produces a checklist issue per
release. The release workflow reads the linked issue via the API and refuses to publish while
any box is unticked or any evidence field is empty. Release discipline that lives in a
maintainer's head does not survive a volunteer project (QA-31); release discipline that lives in
a template a workflow enforces does.

**A. Preconditions**
- Version decided in all three streams; `VERSIONING.md` rules applied.
- README maintenance status (`maintained` / `seeking-maintainers` / `archived`) and supported-OS
  matrix current — R-107, and the workflow refuses to tag without them.
- Last-good tag recorded, with its `BUILDINFO`, for the roll-forward path.

**B. Green (automated, all must be green)**
- QA's T0–T2 tiers; Linux core check; rename drill; `reuse lint`; dependency licence gate;
  licence-drift check; DCO post-merge audit; SBOM generated and schema-valid; attestations
  produced and verified.

**C. QA gates** — referenced from QA-31, not restated: real-device pass (R-87), soak record
(R-88), canaries green for 24 h, energy protocol recorded, accessibility audits, performance
baselines within 20%, upgrade-from-previous-release with a migrated store, zero open P0/P1,
flake rate ≤1%.

**D. Compliance gate** — the seven items in *The compliance release gate*, each with named
evidence.

**E. Provenance (R-108)**
- Source tarball, SBOM, `BUILDINFO`, spec bundle and DMG published with attestations.
- **The non-releasing maintainer** runs `gh attestation verify` on a different machine and
  pastes the output. Having the *other* maintainer verify is what makes this a check rather
  than a ritual.
- The clean-machine build has been performed by a named human this cycle, with device, OS and
  elapsed time recorded.

**F. Submission**
- Build uploaded; phased release **on**; medical-device declaration confirmed present for EEA,
  UK and US with a screenshot (R-109); DSA trader status confirmed present and correct (R-111);
  release notes denylist-clean (R-113); demo mode timed walkthrough under 10 minutes (R-114).

**G. Post-release**
- Rollback decision owner **named before the rollout starts**, with pre-committed criteria.
- 72-hour observation window on crash, hang and MetricKit background-exit counters before
  advancing the phased release.
- TestFlight external build refreshed if it is within 30 days of its 90-day expiry.
- `RELEASE-HISTORY.md` updated with the releasing maintainer (R-105a/b evidence).

### TestFlight, and running an OSS beta cohort

Platform facts as the QA lead established them [47, 48]: 100 internal testers who must be App
Store Connect users, 30 devices each; up to 10,000 external testers by email or public link with
tester criteria and a cap; Beta App Review on the first build of each version for external
testers; builds expire 90 days after upload, with no extension.

The OSS-specific problems, and the answers:

1. **Beta access must never be a sponsor perk.** R-110 forbids it, and the CRA analysis is why it
   matters beyond principle: Commission draft guidance ¶62 treats access to software, essential
   functionality or *updates* conditioned on donating as de facto charging a price, which places
   the product on the market [41]. "Supporters get TestFlight first" is the textbook instance.
   So the public link is open; if we cap it, the cap is capacity-based, stated publicly, and the
   waiting list is first-come, never donation-ordered. This is one of the release-gate audit
   items, not a good intention.
2. **Be exact about what the beta reports.** R-37 means our build reports nothing outbound. But
   TestFlight itself gives Apple crash and usage data. Claiming "zero telemetry" and being
   caught out would cost more than the recruiting benefit. The "What to Test" text and the
   landing page say: *this build sends nothing to us; Apple's TestFlight collects crash and usage
   data under Apple's terms, which we can see in aggregate and which we cannot switch off.* For a
   privacy-positioned health app, that precision is a recruiting asset.
3. **Internal testers must be App Store Connect users**, so with two maintainers the internal
   group is the two of us. Do not add community testers as internal to dodge Beta App Review;
   it grants App Store Connect access to strangers.
4. **Cadence outruns expiry.** A build every ≤60 days (QA-37). A scheduled job queries the ASC
   API for the latest external build's `expirationDate` and opens a P2 issue at 30 days
   remaining, P1 at 14. A silently lapsed cohort must be rebuilt from scratch, which for a
   volunteer project during a quiet period is a real loss.
5. **Recruit where the primary persona already is**, and use an asset nobody else in this
   category has: the reference receiver. Someone who has run `docker compose up` and seen a
   panel populate is a qualified tester who understands what they are testing. The receiver
   quickstart therefore ends with the TestFlight link, and the HACS repository's `info.md`
   carries it too.
6. **Contributors are not testers** (QA-30). The build-from-source path with a free personal
   team requires no App Store Connect access and no Apple Developer Program membership, and it
   is a required PR check so it cannot rot.

### Staged rollout, and rollback when you cannot roll back

**Phased release** distributes over seven days at 1, 2, 5, 10, 20, 50 and 100 percent to users
with automatic updates on; users who update manually get the new version immediately regardless
of the phase. It can be paused for up to 30 cumulative days with no limit on the number of
pauses, and can be pushed to 100% manually at any point [2, secondary]. Enable it always.

**Apple's position, in Apple's words: "it's not possible to revert to a previous version on the
App Store. You must create and submit a new version."** [1] So the rollback design is a
containment design, in four escalating steps, each with a named precondition:

1. **Pause the phased release.** The only fast lever. It stops expansion; it does not retract the
   build from users who already have it. First action whenever a halt threshold is crossed.
2. **Roll forward.** Rebuild the last-good tag with an incremented version *and* build number,
   and request expedited review. **Precondition: the last-good tag must still build today.**
   This is the strongest business justification for R-108's toolchain and dependency pinning —
   not purity, but the ability to reproduce a known-good build under time pressure. Record the
   last-good tag's `BUILDINFO` at every release so this is mechanical rather than archaeological.
3. **Remove from sale.** Stops new downloads. Does not remove the app from devices, and it
   delists us — losing the R-107 credibility signal and the HACS and Grafana acquisition
   channels. Reserve for a defect that destroys user data or leaks it.
4. **Advisory.** R-38's signed advisory feed is fetched on user-visible foreground launch. It can
   carry a "this version has a known correctness defect; here is what to do" notice.

The asymmetry in step 4 must be stated plainly in `CONTINUITY.md` and in the incident runbook:

> We can **inform** essentially every user within one foreground launch. We cannot **change**
> what their installed app does. There is no remote configuration and no feature flag service,
> because R-32 and R-37 forbid one and the wedge depends on that. Containment is therefore
> "pause, tell the truth, roll forward fast" — never "flip a switch".

**Pre-committed rollout criteria**, decided before the rollout starts and recorded in the
release issue with a named owner: crash-free session rate versus the previous release's
baseline; MetricKit background-exit counters, specifically
`cumulativeMemoryResourceLimitExitCount` and `cumulativeSuspendedWithLockedFileExitCount`, since
the latter fires on suspension while holding a file or SQLite lock and is exactly the shape of a
mid-export suspension; and any single credible P1 correctness report — because by R-88's own
definition a reconciliation discrepancy is a P1, and a correctness defect in the correctness
product does not get graded on volume.

---

## Reproducible build-from-source (R-108)

### What we can and cannot honestly claim

Three distinct claims. We can make two.

| Claim | Can we? | What backs it |
|---|---|---|
| **Auditable source** — the exact source of any released version is public and identifiable | **Yes** | Signed annotated tag; `source-<tag>.tar.gz` with a published SHA-256; `BUILDINFO` recording the exact commit |
| **Verifiable provenance** — this artifact was built from that source, by that workflow, on that runner | **Yes**, for artifacts *we* build | Sigstore-backed GitHub artifact attestations (`actions/attest`, SLSA provenance v1 predicate); public repositories sign via the Sigstore public-good instance and land in the Rekor transparency log, so verification does not require trusting us [22, 23]. Verified with `gh attestation verify --repo … --signer-workflow … --deny-self-hosted-runners` [24] |
| **Reproducible binary** — an independent party rebuilds the App Store binary bit-for-bit and it matches | **No, and we say why** | C-09. Apple re-signs and FairPlay-encrypts App Store binaries; what a user downloads is not what we uploaded. No engineering on our side changes this |

Two further precisions, because over-claiming here would be worse than under-claiming:

- **R-84 is about export output, not build output.** R-84 requires byte-determinism of the data
  we emit given identical input. That is a testable product property (QA-07, property P8) and we
  will hold it. It says nothing about whether the *compiler* is deterministic. Conflating the two
  is the most likely way this document gets misread, so `PROVENANCE.md` states the distinction
  explicitly.
- **We have not verified that Swift compilation is bit-reproducible**, and must not assume it.
  Debug-info paths, `Info.plist` processing and link ordering are all plausible sources of
  variance. So the claim is scoped to: *the same source with the same pinned toolchain produces
  a functionally equivalent build, and the artifacts we publish are cryptographically bound to
  the source and the workflow that produced them.* Bit-reproducible Swift builds are worth
  tracking as an ecosystem development; they are not something to promise in a README.

### The four things we actually build

**1. Toolchain pinning.**

- `.swift-version` = `6.3.3`, consumed by `swiftly` for the Linux and core paths.
- `.xcode-version` = `26.6` plus the exact build number. **This is not redundant with
  `.swift-version`**: on Apple platforms the SDK always comes from the currently selected Xcode,
  and Xcode's Swift toolchain is always a distinct build from the swift.org toolchain of the same
  nominal version [45]. Pinning only `.swift-version` produces a build that is reproducible on
  Linux and unpinned on Darwin — a trap worth naming.
- Pinned runner image labels, never `macos-latest` or `ubuntu-latest`, on the release path.
- A `scripts/assert-toolchain.sh` that runs first in every build and fails with a human-readable
  message naming the expected and actual versions. A contributor whose Xcode is one point
  release ahead should get a sentence, not a linker error.
- `BUILDINFO-<tag>.json` emitted into every release, recording: git commit, Swift version, Xcode
  version and build, macOS version, SDK version, runner image label, `Package.resolved` digest,
  generator version, and the SHA-256 of every published artifact.

**2. Dependency pinning.**

- `Package.resolved` committed at the repository root and at the Xcode workspace path.
- The one runtime dependency declared with an `.exact()` requirement, not a range.
- **`xcodebuild -disableAutomaticPackageResolution` in every CI invocation**, so that a re-tagged
  upstream fails the build rather than silently changing it. Without this flag SPM will happily
  update `Package.resolved` mid-build if an upstream tag has moved, which defeats the entire
  purpose of committing it [44].
- `policycheck deps` rejects branch requirements, unpinned revisions, and forks without a
  recorded reason in `dependencies/`.

**3. The stranger test, run every release, two ways.**

- **Automated, every PR and every release:** a `build-from-source-clean` job on a fresh runner
  that clones only the tag, with no cache, no secrets and no Apple team, and executes the
  README's build instructions **by extracting the fenced `bash` blocks under the "Build from
  source" heading and running them verbatim.** The README cannot drift from reality, because the
  test *is* the README. This is the single highest-leverage trick in this section: every project
  that keeps build instructions in prose and the build in CI ends up with instructions that do
  not work, and nobody notices until a stranger tries.
- **Human, once per release:** a named non-maintainer builds and runs the app on their own
  machine from the tag using only the README, and records device, OS, elapsed time and any
  friction in the release issue. This is what R-108 literally asks for. The CI job exists so
  this is never a surprise.

**4. The provenance bundle, published per release.**

| Artifact | Attested | Notes |
|---|---|---|
| `source-<tag>.tar.gz` + SHA-256 | Yes | `git archive` from the signed tag |
| `sbom-<tag>.spdx.json`, `sbom-<tag>.cdx.json` | Yes | `syft` over the repository, with the Swift `Package.resolved` cataloger explicitly selected — it parses resolved-file versions 1, 2 and 3 but is not enabled by default for every scan target, and Anchore's own documentation concedes Swift coverage is less complete than Java or Python [31, 32]. So the SBOM is honestly **top-level dependencies**, which is also the CRA floor [43] |
| `BUILDINFO-<tag>.json` | Yes | Above |
| `spec-<specver>.tar.gz` | Yes | Schema and fixtures, CC0-1.0, so a receiver author can vendor it with no licence question |
| `<slug>-companion-<tag>.dmg` + SHA-256 | Yes | Signed, notarised, stapled |
| Reference receiver image | Yes | Multi-arch, GHCR, so the R-115 quickstart needs no build |
| An iOS `.ipa` | **Not published** | We do not distribute one. Publishing a signed-for-us `.ipa` would imply a verifiable relationship to the store binary that does not exist |

**5. The sentence we use everywhere.** Verbatim in `README.md` and `PROVENANCE.md`:

> You can read the exact source of any released version, verify that every artifact we publish
> came from that source, and build a working app yourself from a clean machine. You cannot verify
> that the App Store binary matches, because Apple re-signs and encrypts App Store binaries
> before delivering them. If bit-for-bit verification matters to you, build from source — and
> that path is tested on every release precisely so that it works.

The last clause is the honest answer to C-09, and it is only credible because of the stranger
test. Publishing the claim without the test would be the kind of thing this project exists not
to do.

---

## Governance artifact manifest

| File | Purpose | Contents outline | Acceptance |
|---|---|---|---|
| `LICENSE` | The grant GitHub's detector and SPDX tooling read | **Verbatim, unmodified** AGPL-3.0 text | Byte-identical to the canonical text, asserted in CI; GitHub reports AGPL-3.0; present in commit 1 (**R-100**) |
| `COPYING` | The project's licensing statement, including the §7 permission | Which licence applies to which part of the tree (code AGPL-3.0, docs CC BY 4.0, spec and fixtures CC0-1.0); then a clearly delimited **"Additional permission under GNU AGPL version 3 section 7"** block appended *after* and *outside* the verbatim licence text, since the licence text itself may not be modified | The §7 block is byte-identical to the block in `CONTRIBUTING.md` and in the DCO assertion, asserted by `policycheck licence-text`. **[R-112]** on the permission wording |
| `LICENSES/` | REUSE compliance | `AGPL-3.0-only.txt`, `CC-BY-4.0.txt`, `CC0-1.0.txt`, plus a verbatim file for every SPDX identifier used anywhere in the tree | `reuse lint` exits 0; every file name is a valid SPDX identifier with an extension [28, 29] |
| `REUSE.toml` | Licensing for files that cannot carry a header | Schema `version = 1`; per-directory `SPDX-FileCopyrightText` and `SPDX-License-Identifier` for `spec/**` (CC0-1.0), `fixtures/**`, assets, `receiver/dashboards/**` | `reuse lint` exits 0 [28] |
| `NOTICE` | Attribution — a **legal obligation** under permissive licences, not a courtesy | Generated from the resolved dependency graph; rendered verbatim in an in-app Acknowledgements screen | CI regenerates and fails the build if stale (OSS-18); adding a dependency without regenerating breaks the build |
| `README.md` | The only thing most people read | One-line description; the "not a medical device" sentence (**R-109**); machine-readable maintenance status and supported-OS matrix (**R-107**); the locked-device and best-effort-scheduling disclosure (**R-63**); the freshness target N (**R-24**); the honest provenance sentence; the advisory endpoint (**R-38**); numbered build-from-source commands **that CI executes**; explicit "what this deliberately does not do"; links to every file below | The `build-from-source-clean` job parses and runs its `bash` blocks; the release workflow refuses to tag without a current status line and OS matrix |
| `CONTRIBUTING.md` | Contribution mechanics and the licence grant | DCO 1.1 verbatim with a copy-pasteable `git commit -s`; the **§7 permission restated in full** and incorporated into the sign-off assertion; inbound = outbound stated explicitly; the licence-change rule; the new-dependency process; the changelog-fragment requirement; **no real health data, ever, including your own** (QA-06); expected review latency; the unsigned-commit recovery procedure | Both licence statements present and identical to `COPYING`; reviewed at every maintainer change (**R-101**, OSS-05) |
| `CODE_OF_CONDUCT.md` | Community norm. Not a legal obligation | **Contributor Covenant 3.0** (July 2025) [33, 34], with the reporting and enforcement sections filled in. Note GitHub's built-in template still ships an older version, so it is added manually. **Plus an honest limitation paragraph**: see the open question below | Enforcement contact is an address a test message reaches; the limitation paragraph names either an agreed external escalation or states plainly that none exists (OSS-08) |
| `SECURITY.md` | Vulnerability intake and coordinated disclosure | GitHub private vulnerability reporting **enabled**; ≤14-day initial response target [35]; 90-day default embargo, negotiable; **scope, stated precisely** — a redaction defect (RK-6), a ledger or anti-coercion bypass (R-41), a credential-storage defect (R-33) are vulnerabilities; "the app can send data to a host the user configured" is not; no bounty; how a fix is disclosed via R-38's advisory feed and the changelog; and a note that the process is deliberately built so it *could* meet CRA Article 14's 24 h / 72 h / 14-day cadence if scope ever changed [42] | Private reporting enabled; a test report is acknowledged within target; linked from the README |
| `SUPPORT.md` | Deflect support load, set expectations honestly | What is supported and what is not; the supported-OS and supported-HA-version windows; volunteer best-effort; Discussions for questions, Issues for bugs; **how to redact a diagnostic bundle before attaching it** (R-26) | Present; linked from the README and from the issue templates |
| `MAINTAINERS.md` | Who decides, who can be reached, how succession works | Per maintainer: GitHub handle, scope, contactable address, **and Apple role** (Account Holder / Admin) with which certificate-access grants they hold; the onboarding checklist including the ASC role grants and the R-105a/R-105b release obligations; the offboarding checklist including key revocation; the 90-day dormancy trigger; quarterly review date | Present before v1.0; reviewed quarterly; both maintainers named with an Apple role (**R-105a**) |
| `GOVERNANCE.md` | What happens when there is disagreement, or nobody | Decision-making (documented BDFL converting to a maintainer team); how maintainers are added and removed; **the licence-change rule: any change requires the consent of all copyright holders**; the dormancy trigger; the dated CRA/SBOM re-assessment triggers | Both statements present (OSS-05). *Note: the brief's manifest omitted this file; R-101's licence-change rule needs a home and this is it* |
| `CONTINUITY.md` | **R-106.** What happens if maintenance stops | The signing-identity inventory as *what exists, who can regenerate it, what breaks if it lapses* — never key material; Account Holder transfer as an Apple Developer Support process, plus the App Transfer route; the accounts nobody thinks about (Grafana Cloud, the `hacs/default` submitting identity, GHCR); the fork instructions including what must be renamed; the "we can inform but not change" asymmetry; and the **corrected bus-factor statement** — see below | Present before v1.0; reviewed by someone outside the project (**R-106**) |
| `TRADEMARK.md` | What a forker may and may not call their build | Derived from the Model Trademark Guidelines [49]; nominative use permitted, product naming and logo use not | Published in-repo and on the landing page. **Blocked on D-06** (OSS-21) |
| `VERSIONING.md` | The three streams and their relationship | The table above; the five rules; the spec-freeze policy; what counts as public API for each stream | Present; `policycheck spec-freeze` implements rule 3 |
| `PROVENANCE.md` | What R-108 claims and what it does not | The three-claim table; the verification commands a reader can run themselves; the R-84-is-not-build-determinism precision; the honest sentence | Present; a reader following it can verify a release unaided |
| `CHANGELOG.md` + `changes/unreleased/` | The artifact users check to decide whether we are alive | Keep a Changelog 1.1.0 [50] plus the three project-specific sections | Fragment required on any PR touching `Sources/`; a release without a changelog entry cannot be tagged |
| `CODEOWNERS` | Route review; make ownership legible | Every top-level path owned. `spec/` and `compliance/` owned by both maintainers jointly, so a frozen spec or a compliance denylist cannot be changed by one person | Reviewed at every maintainer change; no unowned top-level path (checked in CI) |
| Branch protection / ruleset on `main` | Stop one person being the only thing between a bad commit and users | Linear history; ≥1 approving review; **no direct pushes**; required checks: Linux core, macOS build+test, DCO, `reuse lint`, licence gate, licence-drift, rename drill, changelog fragment, `build-from-source-clean`, spec-freeze; no force-push; no deletion; admin bypass **disabled** once there are two maintainers; **squash-merge configured to preserve commit trailers** (see the DCO section) | Settings audit recorded in the release issue; a force-push attempt is rejected; every required check passes on a fork PR (**R-85**) |
| `.github/ISSUE_TEMPLATE/bug.yml` | Actionable bug reports without health data | Structured fields for OS, device, app version, spec version, destination type, reason code from the journal (R-21's enumerated outcomes); **a prominent warning not to paste real health data**, with a link to the redacted-bundle flow (R-26) | Present; a report containing an obvious health value is caught by a bot comment, and the guidance is in the form itself, not in a wiki |
| `.github/ISSUE_TEMPLATE/dependency.yml` | New-dependency proposals | What it does; why a first-party implementation was rejected; SPDX identifier and licence file digest; whether it builds on Linux; transitive dependency list; maintenance signal; the §7 question if it is copyleft | A dependency PR without a linked, completed proposal cannot merge (OSS-17) |
| `.github/ISSUE_TEMPLATE/release.yml` | The release checklist | Sections A–G above | The release workflow reads it and refuses to publish while any box is unticked (QA-31) |
| `.github/PULL_REQUEST_TEMPLATE.md` | Reviewer checklist | DCO signed **and the §7 grant acknowledged**; tests at the lowest layer that can catch it; changelog fragment; docs updated; no new dependency without a proposal and an ADR; no real health data in the diff; redaction rules reviewed (R-51); frozen spec untouched; accessibility audited if UI changed | Present; the §7 checkbox is required |
| `PrivacyInfo.xcprivacy` | Apple privacy manifest, and an R-36/R-37 assertion | Zero tracking domains; required-reason API declarations | CI parses it and fails on any tracking domain or on a dependency without a manifest |
| `hacs.json`, `custom_components/health_export/manifest.json`, `brand/icon.png` | **R-116** | See *Distribution and channel artifacts* | HACS Action and hassfest pass with no errors and no ignores |
| `docs/adr/` | Decision record | ADR-0001 exists; the twelve I propose below | Every ADR referenced from the requirement it implements |

### The two places this manifest must be honest rather than complete

**`CODE_OF_CONDUCT.md`.** An unenforced code of conduct is worse than none, because it advertises
a promise the project cannot keep. With two maintainers and D-10 still open, there is no
credible process for a complaint *against* a maintainer. Two acceptable resolutions: name a
specific external person who has agreed in writing to receive such complaints, or state plainly
in the document that enforcement rests with the maintainers and that no external escalation
exists. I will not ship a document that implies a process we cannot run. This is the governance
lead's open question 6, and it is still open — see *Open questions*.

**`CONTINUITY.md`, and a bus-factor statement that D-03 changed.** R-106's original wording
assumed individual enrolment and told the reader the App Store channel had a bus factor of one.
D-03 fixes that — and introduces a different single point of failure that must be stated with
the same candour:

> Under organisation enrolment the App Store channel no longer depends on one person. It now
> depends on the continued existence and good standing of the legal entity that holds the
> enrolment. If that entity is dissolved, the Apple Developer Program membership goes with it,
> and recovering the listing is an Apple Developer Support process with no guaranteed outcome.
> The mitigations are unchanged in kind: build-from-source is a first-class, tested path
> (R-108), and the licence permits a rebranded fork.

### REUSE, SPDX and SBOM — are these becoming obligations?

**REUSE: not a statutory obligation; becoming a de facto one.** No statute requires it. But
downstream packagers are adopting it as a gate — Arch Linux's RFC 0052 adopts REUSE for package
licence linting across all package sources [30] — and it is the cheapest route to a defensible
licence audit. REUSE 3.3 with `reuse lint` in CI from commit one [28, 29]. Retrofitting SPDX
headers across thousands of files costs days; adopting it now costs a file header template.

**SBOM: not yet an obligation for us, and the governance lead's analysis holds.** CRA Annex I
Part II(1) requires a machine-readable SBOM covering at least top-level dependencies; it sits in
the *technical documentation* and need not be published; it becomes enforceable on 11 December
2027, and only for products in scope; and Article 13(24) reserves the format to a future
implementing act that does not yet exist [43]. We generate SPDX and CycloneDX anyway, because it
is a few lines of CI and it is the first artifact a distribution packager or a security
researcher asks for.

**Three dated re-assessment triggers**, recorded in `GOVERNANCE.md` with a review date rather
than left to memory:

1. Any decision to charge for the binary (D-08 reversal) — makes us a CRA manufacturer, at which
   point the SBOM, a declared support period and Article 14 reporting all become obligations
   with fines attached.
2. **D-03's steward question.** The governance lead's finding is counterintuitive and now live:
   where the publisher is a natural person the free community version is outside CRA scope
   entirely, whereas a *legal person* still picks up steward obligations [41]. D-03 chose a
   legal entity. So the analysis that put us out of scope was written for a publisher we no
   longer are. **R-112's opinion must cover this explicitly**, and the PRD's own note on D-03
   says as much.
3. Formal adoption of C(2026) 5252 in a form that differs from the draft ¶61 donations analysis
   — the whole donations carve-out rests on draft guidance [41].

Note the date sensitivity: CRA Article 14 reporting obligations begin **11 September 2026**,
eight days from this document [42]. They do not reach us on the current analysis, and they are
not retroactive to knowledge acquired before that date. `SECURITY.md` should nonetheless not
promise anything incompatible with that cadence, which is why the disclosure design above is
built to be capable of it.

---

## DCO and the §7 permission grant

### The construction

ADR-0001 requires that the §7 additional permission be granted by every contributor, with the
text in `COPYING`, restated in `CONTRIBUTING.md`, and incorporated into the DCO assertion so
that signing off is an affirmative grant rather than an implied one. R-101 requires CI to reject
an unsigned commit.

**Do not modify the DCO text.** DCO 1.1 is the Linux Foundation's, and its low friction comes
entirely from being universally recognised [27]. A modified "DCO" is a contributor licence
agreement wearing a costume: it loses the recognition, invites scrutiny, and gives us a
two-class contribution history. So the grant is layered on rather than baked in:

```
CONTRIBUTING.md  (extract)

  By adding a `Signed-off-by:` trailer to a commit you certify the Developer
  Certificate of Origin 1.1, reproduced in full below, AND you additionally grant,
  for your contribution, the additional permission under section 7 of the GNU
  Affero General Public License version 3 that is reproduced verbatim in COPYING
  under "Additional permission under GNU AGPL version 3 section 7", which permits
  distribution of this work through application stores whose terms are otherwise
  incompatible with section 6 of that licence.

  This grant is irrevocable for contributions already made, is a condition of
  contribution, and is the mechanism by which this project can be distributed on
  the Apple App Store. If you are not willing to grant it, please do not send a
  pull request; open an issue instead and we will discuss the change.
```

Three design points:

1. **The commit trailer stays exactly `Signed-off-by:`.** No second trailer. A custom trailer
   would break the DCO app, confuse every contributor who has ever signed off on anything, and
   buy nothing that incorporation-by-reference does not.
2. **Belt and braces on the load-bearing part.** The PR template carries a required checkbox
   restating the §7 grant in one sentence. The PR body is part of the permanent merge record, so
   this yields a second, timestamped, per-contribution artifact at essentially zero friction.
   Since ADR-0001 says an ambiguous grant reopens the veto, a second record is proportionate.
3. **The three copies of the text must not drift.** `policycheck licence-text` asserts that the
   §7 block in `COPYING`, the block quoted in `CONTRIBUTING.md`, and the sentence in the PR
   template are byte-identical to a canonical `compliance/section7.txt`. Three hand-maintained
   copies of a legal grant will diverge within a year otherwise, and a divergent grant is worse
   than no grant.

**[R-112]** The permission wording itself, and the "irrevocable / condition of contribution"
phrasing, need the paid opinion. ADR-0001 already flags the text for review; this is the same
item, and it gates the first external PR rather than v1.0.

### How CI rejects an unsigned commit

Four layers, because each one alone has a hole, and the holes are well known:

1. **The DCO GitHub App** (`probot/dco`) as a **required status check** on `main`. It creates a
   check that fails when any non-merge, non-bot commit in a PR lacks a valid `Signed-off-by`
   whose email matches the commit author, and `@dcoapp recheck` recovers PRs stuck after an
   outage [25]. Free, needs no secrets, works on fork PRs — so it satisfies R-85 as well as
   R-101.
2. **GitHub's native "Require contributors to sign off on web-based commits."** Enabled at the
   repository, and as an organisation repository default. It covers only web-UI commits, and
   CLI commits still need `-s` [26]. That sounds redundant with layer 1 until you notice that
   web-UI documentation typo fixes are the single most common source of unsigned commits, and
   they arrive from people who will not debug a failing check.
3. **No direct pushes to `main`.** Without this, layer 1 never runs on the commit at all, because
   the DCO app is PR-scoped. This is the gap most DCO-enforced repositories actually have, and
   it costs one branch-protection setting to close.
4. **Squash-merge trailer preservation.** GitHub's squash merge composes a new commit message
   from the PR title and body by default, and **the `Signed-off-by` trailers of the squashed
   commits can be lost.** Either set the repository's squash-merge message default to "pull
   request title and commit details", or forbid squash merges and require rebase or merge
   commits with linear history. **This is the single most common way a DCO-enforced repository
   ends up with unsigned commits on `main` while every PR check was green**, and it deserves to
   be in the branch-protection acceptance criteria rather than in someone's memory.

Plus the check that makes R-101 true in the durable sense rather than the per-PR sense:

5. **A post-merge audit**, scheduled weekly and again as a release gate:

```bash
git log --no-merges --format='%H %ae %(trailers:key=Signed-off-by,valueonly)' \
    "$LAST_RELEASE_TAG..main"
# fail if any line has an empty trailer field, or a trailer email that does not
# match the author email
```

This catches the squash-merge hole, any admin bypass, and any history that arrived before the
app was installed. It is also the evidence R-101's acceptance criterion needs: not "the check
exists" but "no unsigned commit is present in the release".

### What DCO does not give us, stated plainly

No express patent grant beyond what AGPLv3 §11 already provides between the licence's parties;
no ability to relicense without unanimous consent of all copyright holders. ADR-0001 accepted
both, and `GOVERNANCE.md` records the licence-change rule so a future maintainer does not assume
otherwise.

### Recovery when an unsigned commit reaches `main`

It will happen once. The procedure is documented in `CONTRIBUTING.md` rather than improvised:

- If the branch is unmerged: the contributor amends and force-pushes their own branch.
- If it is merged: obtain a written retroactive sign-off in the PR thread, and record it in
  `compliance/dco-exceptions.md` with the commit SHA, the contributor, the date and a link.
- Do **not** rewrite `main`. Every fork, clone and attestation breaks, which is worse.
- Do **not** ignore it. An ambiguous grant is exactly what ADR-0001 says reopens the App Store
  veto, and the exceptions file is the audit trail that says we noticed.

---

## The compliance release gate

Design principle: an automated check that fails the build, or a named human sign-off with
attached evidence that a workflow verifies exists. Nothing in between, because "the maintainer
remembers to check" is how compliance requirements quietly become aspirations.

`Tools/policycheck` is a Linux-buildable Swift executable, so it runs on the cheapest tier, on
fork PRs, with no secrets, and is itself unit-tested.

| Req | What must be true | Automated? | Mechanism | Effect on failure |
|---|---|---|---|---|
| **R-109** medical device | (a) regulated-medical-device status declared in App Store Connect for EEA, UK and US [36]; (b) the exact "not a medical device" sentence present in first-run copy, the About screen, the README and the landing page | (b) fully; (a) no | (b) `policycheck disclaimer` asserts the canonical sentence from `compliance/disclaimer.txt` appears in all four surfaces **in every shipped locale** — a half-translated disclaimer is a disclosure defect, not a polish defect; (a) there is no public API for the declaration, so it is a screenshot in the release issue | (b) build fails; (a) release blocked |
| **R-111** DSA trader | Trader status declared before first submission, against the entity's address (D-13); Apple publishes it across all 27 EU territories [37, 38] | No | One-time setup, then a per-release confirmation that it is present and still correct, with a screenshot | Release blocked |
| **R-110** no sponsor gating | No functionality, update path, build artifact or beta seat is conditioned on donating or sponsoring | Largely | `policycheck feature-flags`: enumerate every feature flag, build configuration, compile condition and entitlement gate; fail on any reference to `sponsor`, `donat`, `patron`, `supporter`, `tier`, `backer`, `premium`, `unlock`, `entitlement receipt`; assert **no StoreKit symbol is linked** in any target; assert every release asset is downloadable without authentication. Manual half: confirm the TestFlight external group is not filtered by a donor list and the public link has no donation precondition | Build fails; and the manual half blocks the release |
| **R-113** no medical claims | No published copy claims medical, diagnostic, clinical, FDA/CE or HIPAA status | Yes | `policycheck copy-denylist` over **all** published copy: `store/**` (App Store name, subtitle, description, keywords, what's-new), README, landing page source, `CHANGELOG.md`, generated release notes, the in-app string catalogues, the HACS `info.md`, the Grafana dashboard title/description/README, and the TestFlight "What to Test" text | Build fails on any unallowlisted match |
| **R-42 / R-41** | No feature interprets, diagnoses, screens or recommends clinical action; destinations, credentials-in-use and the egress ledger can never be hidden or gated away | No (feature review) | A required PR-template checkbox and a release-issue sign-off. Weak automated proxy: a UI test asserts the destinations screen and the egress ledger are reachable from the navigation root without any gate | Release blocked |
| **R-36** no third-party SDK | No non-first-party binary dependency is linked; the privacy manifest matches | Yes | Linked-framework scan against an allowlist; `PrivacyInfo.xcprivacy` parsed for tracking domains | Build fails |
| Licence hygiene | `reuse lint` clean; every dependency licence on the allowlist; `LICENSE` byte-identical to canonical AGPL-3.0; the §7 text identical in all three places; `NOTICE` not stale; `licences.lock` unchanged | Yes | As described in the dependency policy | Build fails |
| **R-112** legal opinion | An opinion is on file and referenced from the relevant ADR before charging, GPL-family adoption, or incorporation | No | ADR-0001 and the D-03 CRA ADR carry the reference | Release blocked if a trigger has fired |

### The two design choices that make this real rather than theatre

**1. App Store metadata lives in the repository.** `store/<locale>/{name,subtitle,description,`
`keywords,whats-new,promotional-text}.txt`, and submission copies from there into App Store
Connect. This is not tidiness. R-113 is unenforceable otherwise: the highest-risk copy in the
entire project is marketing copy, it is what turns a data-mover into a medical-device claim, and
if it lives only in App Store Connect then CI cannot see it and no check can exist. Making the
store copy a reviewed, diffable, denylist-checked artifact is the single change that turns R-113
from an intention into a gate.

**2. The denylist needs a context allowlist, or it will be switched off within a month.** The
sentence *"This app is not a medical device and does not diagnose, treat or screen for any
condition"* contains four denylisted terms and must pass. Implementation:

- Match the denylist: `diagnos*`, `clinical*`, `treat*`, `screen(ing)`, `medical device`, `FDA`,
  `510(k)`, `CE mark*`, `HIPAA`, `PHI`, `prescription`, `therap*`, `monitor your condition`,
  `detect*`, `symptom*`, `disease`.
- Discard matches inside a sentence that also matches a negation pattern (`not a`, `does not`,
  `we do not`, `no ... claim`).
- Require every remaining suppression to appear in `compliance/allowlist.txt` with a one-line
  reason, and count suppressions in the CI output so growth is visible.

Suppressions are reviewed like code. A denylist with a broad ignore rule is the same thing as no
denylist, and it costs more because it looks like diligence.

---

## Distribution and channel artifacts

### R-114 — demo mode and the synthetic dataset, with one generator

**One generator, and the boundary is explicit.** `Tools/corpusgen` is Linux-buildable, seeded and
deterministic. It produces QA's T0/T1/T2 corpora (QA-04) *and* the demo bundle. QA owns the
edge-case catalogue and the statistical model; I own the executable's packaging, its CC0-1.0
licensing, its attestation, and the loader that release builds use. Building two generators is
the most likely duplication in Stage 3 and this table exists to prevent it.

**Resolving QA's open question 11 against QA-38.** QA asked whether demo data should ship in
release builds, and noted the tension with QA-38 (no test-only code in a release build). Both
R-114 and RK-3 need it — App Review must be able to see health functionality on a device with no
Health history, and RK-3 is rated Medium/Critical. The tension resolves structurally rather than
by compromise:

> Demo mode ships in release builds and loads a **read-only, signed resource bundle** through the
> same decoder the wire-format tests use. It does **not** link `ExportTestKit`, the fake
> HealthKit source, or any of the six fault-injection seams. Those remain excluded at compile
> time. The distinction is between *shipping data* and *shipping test machinery*; only the
> former ships.

That belongs in an ADR, because it is the kind of decision a later reviewer will otherwise read
as a violation of QA-38.

**Anti-confusion requirements**, which are mine because they are release-facing. A user who
accidentally exports synthetic data into their Home Assistant statistics has a problem only
hand-editing a database will fix, and in a product whose wedge is trustworthy data, that is a
serious defect:

- Demo mode is labelled on every screen, not just the one where it was enabled.
- Every exported record carries `"demo": true`, and every file gets a `DEMO-` filename prefix.
  This is a wire-format field, so it is a spec decision and must land in `spec/v1.0.0`, not be
  retrofitted.
- Sending demo data to a real configured destination requires a second, explicit confirmation
  naming the destination.
- Every demo run is recorded in the R-30 egress ledger as a demo run.

**Acceptance (R-114):** a new engineer on a clean simulator produces a complete export in under
ten minutes. Make it a timed, recorded step in the release checklist, executed by whoever joined
most recently — and if nobody has joined, by the non-releasing maintainer on a wiped simulator.
A ten-minute claim that nobody has timed in six months is not a claim.

### R-115 — the reference receiver and the published dashboard

`receiver/` in the monorepo: one `compose.yaml` bringing up the reference receiver, a
time-series store, and Grafana with the dashboard pre-provisioned. `docker compose up`, then the
quickstart. Published as a multi-arch image to GHCR with a build-provenance attestation so the
quickstart does not require a build.

**The receiver is the executable form of the wire spec.** It validates every payload against the
committed JSON Schema and rejects nonconforming input loudly rather than coping. That makes it a
contract test for us, a reference implementation for third parties, and the thing that makes
R-12's ecosystem argument concrete. It shares the schema with QA-13's payload validation — one
schema, two consumers.

**Licensing split**, extending ADR-0001's reasoning: receiver code AGPL-3.0 like everything else;
the **schema, the fixtures and the dashboard JSON are CC0-1.0**, because a self-hoster copying a
dashboard panel must never have to think about a licence. Interop surface gets zero friction.

**Publishing to the Grafana community catalogue**, and two consequences that shape the repo [21]:

- The mechanics: export the dashboard using the **Classic** model (the newer schema model is not
  accepted by the catalogue), sign in to a Grafana Cloud account, My dashboards → Upload
  dashboard, complete the metadata (screenshots, logo, README), Save and Publish. Later metadata
  changes go through Submit.
- **Consequence 1 — a bus-factor item nobody lists.** The published dashboard is held under
  whichever Grafana account uploaded it. Use an account owned by the entity, with credentials in
  the entity's password manager, and record it in `CONTINUITY.md` alongside the `hacs/default`
  submitting GitHub identity and the GHCR namespace. These are the accounts that get forgotten
  in a handover and then cannot be recovered.
- **Consequence 2 — pin the export model in CI.** A job validates that the committed dashboard
  JSON is Classic-model and renders in the pinned Grafana version in the compose stack.
  Otherwise a Grafana upgrade silently produces a JSON the catalogue will refuse, and we find out
  when we try to publish an update.

R-113's denylist runs over the dashboard title, description and README, because those are
published copy.

### R-116 — the HACS default list

Requirements, from HACS's own documentation, and then the part the brief actually asks about.

**Repository and submission** [16]: public, hosted on GitHub; the `hacs/default` pull request may
be submitted only by the owner or a major contributor; fork `hacs/default`, branch from
`master` (never commit to `master` directly), add the repository to the `integration` file
keeping it sorted and valid JSON. Custom integrations that override or alpha-test core
integrations are not accepted as defaults.

**`hacs.json` at the repository root** [17]: `name` is the only required key. Optional keys that
matter to us: `homeassistant` (minimum HA version — keep this consistent with QA-12's
two-version test matrix), `hacs` (minimum HACS version), `content_in_root`, `zip_release` with
`filename`, `persistent_directory`, `hide_default_branch`, `country`.

**Integration layout** [18]: exactly **one** integration per repository — if there is more than
one subdirectory under `custom_components/`, only the first is managed. All files required to run
must live under `custom_components/<domain>/`.

**`manifest.json`** in the integration directory, with at least `domain`, `documentation`,
`issue_tracker`, `codeowners`, `name`, `version` [18].

**Brand assets** [16, 18, 19]: a `brand/` directory in the repository with at least `icon.png`;
HACS falls back to checking the domain in `home-assistant/brands` if that is absent. Ship
**both** — the in-repo asset and the brands registration — because hassfest has historically
failed on an unregistered domain and the brands pull request has its own external review latency
that we do not control.

**Both workflows must pass with no errors and no ignores before the PR is opened** [16]: the
HACS Action (`hacs/action`) and hassfest (`home-assistant/actions`) [20]. R-116's own acceptance
criterion says the same.

**A full GitHub Release, not just a tag**, created *after* the actions pass. HACS reads the
latest release's tag name as the remote version; publishing tags alone is not enough [16, 17].

**Automated repository checks at review time** [16]: brands, manifest validity, HACS validity,
HACS manifest contains `name`, an `info.md` (or README) with content, not archived, submitter is
the owner or a major contributor, and general repository hygiene — **a description, issues
enabled, and topics defined**.

#### Why this shapes the repository and cannot be bolted on

Four of these are structural, and the honest resolution of the first one is a decision the PM
needs to take now.

1. **One integration per repository, plus release-driven versioning, plus `hacs.json` at the
   repository *root*, is incompatible with a monorepo whose releases are iOS app releases.**
   HACS would read our latest release — an iOS app release — as the integration's version.
   **Decision: a second, small repository** (`open-health-exporter-hass`) containing only
   `custom_components/health_export/`, `hacs.json`, `brand/icon.png` and `info.md`, synced from
   the monorepo by a workflow on `ha/v*` tags, with its own release stream. Deciding this at
   Stage 2 costs a sync workflow and a second, thin set of governance files. Discovering it at
   HACS review costs a repository split with a live user base and a migration. This is exactly
   the "cannot be bolted on" hazard the brief points at, and the resolution is a second repo
   rather than a monorepo tweak.
2. **The `domain` is effectively permanent.** It keys config entries, entity IDs and the brands
   registration. Renaming it invalidates every user's configuration. So it must be functional
   and unbranded (`health_export`), and it must be fixed before the *first HA release*, not
   before the HACS submission. That makes it a D-06 dependency with an earlier deadline than the
   App Store name.
3. **Brands registration is an external pull request with latency we do not control**, and
   hassfest may depend on it. File it early — as soon as the domain is fixed — because it is the
   one item on this list whose schedule belongs to someone else.
4. **Description, topics, issues-enabled and `info.md` are repository settings the HACS bot
   checks.** Individually trivial; collectively they mean the HA repository must exist, be
   public, and be configured before anything can be submitted.

**Sequencing against D-14's wedge-first constraint.** R-116 is a Should for v1 and a Must within
90 days. The Home Assistant *destination* the PRD actually scopes is a preset of the HTTPS
destination and ships without HACS at all; the HACS integration is a separate deliverable. Do
not let HACS work pull scope ahead of the correctness engine. **But do two cheap things early:**
fix the `domain` and file the brands pull request, because both have external latency and
neither costs engineering time.

---

## Dependency policy under AGPL-3.0

The governance lead's dependency policy was written against an MPL-2.0 outbound licence. D-01
changed the outbound licence, and that **inverts part of the table**. The corrected policy:

Outbound is **AGPL-3.0-only, plus the §7 additional permission**. The question for any inbound
dependency is: can this be combined into a work distributed under that licence, *and* can the
combined work still be distributed on the App Store?

### The allowlist (auto-approve on licence; still requires the review PR)

MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, Zlib, CC0-1.0, Unlicense, MPL-2.0, and Apple's
own frameworks. Notes: Apache-2.0 is one-way compatible into GPLv3/AGPLv3, which is why it was a
problem under an MPL outbound and is not one now. MPL-2.0 §3.3 permits distributing the larger
work under AGPL-3.0 with the MPL-licensed files remaining MPL — so which files are MPL must be
recorded in `NOTICE`, not assumed.

### What changed, and the correction that matters

Under AGPL-3.0 outbound, GPL-3.0 and AGPL-3.0 dependencies are **licence-compatible**:
AGPLv3 §13 expressly permits linking or combining a covered work with a work licensed under
GPLv3 into a single combined work, with each part remaining under its own licence [40]. Under
the previously-recommended MPL outbound they were denylisted. So the naive update to the
governance lead's table is to move them onto the allowlist.

**That would be wrong, for a reason that has nothing to do with licence compatibility.**

> The §7 additional permission must cover the **whole combined work** for the App Store
> construction to hold. A third-party GPL-3.0 or AGPL-3.0 dependency whose copyright holders
> have not granted an app-store additional permission reintroduces precisely the
> contributor-veto problem D-02 was designed to close — this time held by parties we cannot ask,
> did not onboard, and have no relationship with. It is the VLC failure mode with the rightsholder
> outside the project.

Therefore: **any copyleft dependency in shipped code requires either (a) the upstream already
granting an app-store or §7-equivalent permission, in writing, or (b) written permission
obtained from every upstream rightsholder, or (c) rejection.** In practice (b) is not achievable
for a volunteer project, so the shipped-code allowlist remains **permissive-only**. This is the
single most important correction to the inherited policy and it should be an ADR, because the
opposite conclusion is the one a careful reader of ADR-0001 would reach unaided.

### The denylist under AGPL-3.0 outbound

- **GPL-2.0-only and LGPL-2.1-only** — not compatible with the v3 family. An "or later" clause
  makes them upgradeable and therefore compatible, so the `-only` versus `-or-later` distinction
  is load-bearing and the licence gate must read the full SPDX expression, not a fuzzy match.
- **LGPL of any version, for shipped app code** — not for licence reasons but because the
  relinking requirement is not satisfiable under iOS distribution constraints. This is the
  specific problem LGPL relicensing failed to solve for VLC, and it survives the change of
  outbound licence unchanged.
- **GPL-3.0 / AGPL-3.0 without an app-store permission** — per the correction above.
- **SSPL, BUSL, Elastic License, Commons Clause and any non-OSI source-available licence** —
  OSS-26 makes this a permanent Won't.
- **No licence at all.** A repository with no licence file grants nothing; "it is on GitHub" is
  not a licence.
- **AI-generated code of unknown provenance** pasted from an unattributed source.

### Criteria beyond the licence

The licence is the easy part. Every new dependency needs a proposal issue answering all of these:

1. **Does it build on Linux, with its tests passing?** If not, it cannot live in a core target
   without breaking R-80's structural enforcement. This is the realistic way the Linux constraint
   gets defeated, so it is criterion one rather than an afterthought.
2. **Transitive dependency count**, enumerated. Each transitive dependency is a separate review.
   Zero is strongly preferred.
3. **Does it execute code at build time?** SPM plugins, code generators and build tools get their
   own review, because they run on a machine holding a signing credential.
4. **Pinned exactly**, with the resolved revision in `Package.resolved`, from a named upstream.
   No branch requirements, no forks without a recorded reason.
5. **Maintenance signal**: last release date, open-issue trend, bus factor, foundation versus
   individual stewardship.
6. **Why not first-party?** A stated, specific rejection of writing it ourselves.
7. **Privacy manifest** present if it touches any required-reason API — otherwise it breaks R-36's
   acceptance.

**Build-time-only carve-out.** Linters, formatters, generators, `syft`, `reuse`, the Xcode project
generator: a wider licence set applies because we do not convey them. This must be an
**enumerated list** in `dependencies/policy.md`, not an assumption — the difference between a
documented carve-out and an assumed one is that the first cannot quietly expand.

### The MQTT review that D-04 requires

D-04 admits MQTT as our first and only non-Apple runtime dependency, "subject to a recorded
dependency review". Stage 2 should run the review, not pre-empt its outcome. The template, with
the specific things that must be established:

- **Candidates:** the SwiftNIO-based MQTT clients (the `mqtt-nio` family and equivalents).
- **Establish and record:** SPDX identifier and the licence file's SHA-256 at the resolved
  revision (Apache-2.0 expected across the NIO ecosystem, which is allowlisted); whether it
  builds and its tests pass on Linux (required both for R-80 and for QA-11's containerised broker
  path); the full transitive graph, which for a NIO-based client is not zero — `swift-nio`,
  `swift-nio-ssl` and likely more; MQTT 5 versus 3.1.1 support; QoS 0/1/2; TLS with a custom CA,
  which R-35 needs for the self-hoster path; client-certificate authentication; persistent
  sessions with `clean_start=false`; and behaviour on broker restart mid-publish.
- **The landmine, and it is a real one.** If the chosen client depends transitively on
  **`swift-log`**, then R-50 — "no `swift-log` dependency in the app target" — is violated by a
  dependency rather than by us. Three possible resolutions, none free: amend R-50 to prohibit
  `swift-log` as a *facade for our own logging* while tolerating it transitively (which is
  probably what R-50 actually meant, since its rationale is preserving `os.Logger`'s
  `%{private}` redaction annotations, and a transitive dependency does not threaten that);
  write a minimal MQTT 3.1.1/5.0 client ourselves, at real cost against an 87 EW budget with no
  contingency; or drop MQTT and reverse D-04. **This needs a PM answer before the review can
  close**, and it is my highest-priority open question.
- **Acceptance criteria are QA-11's test list**, not a separate list. The dependency review and
  the contract tests share one artifact.
- **Output:** an ADR with the completed template, plus `dependencies/mqtt.md` recording the
  maintenance signal and an annual re-review date.

### When a dependency changes licence

OSS-19 as machinery rather than intention.

**Detection.** A `licence-drift` job resolves the graph, extracts each dependency's SPDX
identifier and the SHA-256 of its licence file at the resolved revision, and diffs against a
committed `dependencies/licences.lock`. Any change to the identifier *or* to the licence text
fails the build. Hashing the text as well as the identifier is what catches a quiet edit that
leaves the identifier alone.

**Procedure.**

1. **Pin to the last release under the old licence, immediately.** A licence change is not
   retroactive; the last release under the old terms stays under the old terms. This is always
   the correct first move and it buys the time the rest of the procedure needs.
2. Assess: is the new licence on the allowlist? Is there a community fork? Is the dependency
   replaceable, or load-bearing?
3. Decide within 90 days, record an ADR, and note it in the changelog's **Supply chain** section.
   Users of a health app are entitled to know when the supply chain moves under them.
4. Never silently upgrade across a licence change. Step 1's detection makes that impossible.

**Two AGPL-specific additions.** A dependency that relicenses *to* GPL or AGPL now triggers the
§7 question above, not merely an allowlist question — so a relicence that looks *more* free can
still be disqualifying. And a dependency that moves to a non-OSI source-available licence is an
immediate P1, because OSS-26 makes that a permanent Won't and "genuinely open source" is the
project's first differentiator.

---

## Open questions for the PM

1. **Who enforces the Code of Conduct, by name?** The governance lead's question 6 is still open
   and D-10 makes it worse: with two maintainers there is no credible process for a complaint
   against a maintainer. I need either a named external person who has agreed in writing, or
   permission to state plainly in the document that no external escalation exists. I will not
   ship a CoC that implies a process we cannot run.

2. **A second repository for the Home Assistant integration — confirm.** I recommend it, because
   HACS's one-repository-per-integration model plus release-driven versioning is structurally
   incompatible with our monorepo. It costs a sync workflow and a thin second set of governance
   files now; it costs a repository split with a live user base later.

3. **Mac companion channel: Developer ID with notarisation, or Mac App Store?** I recommend
   Developer ID first. This is not just a distribution question — it determines which
   certificates exist and, because *Access to Cloud Managed Developer ID Certificate* is
   Account-Holder-granted and Admin-only, it determines whether the second maintainer can ship
   the Mac target at all, and therefore how R-105b is scoped.

4. **Is the repository permanently public?** Every cost figure here depends on it, and so does
   something the QA lead's analysis did not reach: artifact attestations are signed by the
   Sigstore **public-good** instance only for public repositories, and that is what lets an
   outsider verify our provenance without trusting our tenant. A private repository would
   downgrade the R-108 claim, not just the CI bill.

5. **R-50 versus D-04.** If the admitted MQTT client depends transitively on `swift-log`, do we
   amend R-50's wording, write our own client, or reverse D-04? A product answer is needed before
   the dependency review can close, and it is on the critical path for the MQTT destination.

6. **D-03's CRA steward question — scope R-112's opinion explicitly.** The governance lead's
   finding is that a *natural person* publishing free FOSS is out of scope entirely, whereas a
   *legal person* picks up Article 24 steward obligations. D-03 chose a legal entity, so the
   analysis that placed us out of scope was written for a publisher we are no longer. This
   determines whether the SBOM and Article 14 reporting are hygiene or obligations.

7. **Does the entity's address satisfy D-13 across all 27 EU territories, and is there a fallback
   if it changes?** Apple publishes it; changing it afterwards is a support process.

8. **Who holds the peripheral accounts?** The Grafana Cloud account that publishes the community
   dashboard, the GitHub identity that submits the `hacs/default` pull request (which must be the
   owner or a major contributor), and the GHCR namespace. All three are individual-account-shaped,
   all three are single points of failure, and all three are what actually gets lost in a
   handover. They belong in `CONTINUITY.md`, but someone has to own them first.

9. **D-06 timing has an earlier deadline than the App Store name suggests.** The Home Assistant
   `domain`, the bundle identifiers and the brands registration must all be fixed before the
   first HA release. Only the App Store display name is late-changeable, and it keeps the app
   record's accumulated reviews. Confirm the clearance search completes before the first HA
   release rather than before v1.0.

---

## ADRs I propose

| # | Title | Why now | What it records |
|---|---|---|---|
| 0002 | Repository and package topology, with the Linux-buildable core as a structural constraint | Every later choice depends on it; retrofitting the seam is the failure mode QA rates Critical | Single package, many targets; `HealthKitAdapter` as a non-product leaf; the four enforcement mechanisms; the generated Xcode project |
| 0003 | Rename survivability under an open D-06 | Bundle IDs and the HA domain are fixed at first release and cannot be changed after | The one-branded-file rule; the unbranded-identifier table; the rename drill as a CI gate |
| 0004 | Release-path split: Xcode Cloud, GitHub Actions, self-hosted Mac | Determines where every credential lives, before any credential exists | The split, the costs, the "each credential where it is least exposed" principle, and the reassessment triggers |
| 0005 | Three-stream versioning and the spec-freeze gate | R-12 requires independence; coupling the streams is the default instinct and is hard to undo | The three streams; the five rules; `policycheck spec-freeze` |
| 0006 | Provenance, not reproducibility (R-108 and C-09) | The claim must be fixed before it appears in a README, and over-claiming here is self-refuting | The three-claim table; the distinction from R-84; the exact public wording |
| 0007 | Mac companion distribution channel | Determines the certificates, the ASC role grants and R-105b's scope | Developer ID plus notarisation for v1; the minimum entitlement set; the new-team notarisation dry run |
| 0008 | Dependency policy under AGPL-3.0, including the §7 gate on copyleft dependencies | The inherited policy was written for an MPL outbound and its update is counterintuitive | The corrected allowlist and denylist; the §7-permission gate; the build-time carve-out |
| 0009 | MQTT client selection | D-04 requires a recorded review; it may reopen R-50 | The completed review template, the transitive graph, and the R-50 resolution the PM chooses |
| 0010 | Demo mode ships in release builds; fault-injection seams do not | R-114 and QA-38 appear to conflict and a later reviewer will read the resolution as a violation | The data-versus-machinery distinction; the anti-confusion requirements; `"demo": true` as a spec field |
| 0011 | A separate repository for the Home Assistant integration | HACS's constraints are structural and the cost of discovering them late is a repo split | The four structural constraints; the sync workflow; the permanent `domain` |
| 0012 | DCO plus the §7 grant: construction and enforcement | R-101 is load-bearing rather than hygiene per ADR-0001, and the squash-merge hazard is silent | Unmodified DCO 1.1 with incorporation by reference; the five enforcement layers; the exceptions procedure |
| 0013 | No remote kill switch; the advisory feed informs but cannot change behaviour | The absence must be a recorded decision, not an omission discovered during an incident | R-32/R-37 forbid remote configuration; containment is pause, disclose, roll forward; pre-committed rollout criteria |

---

## Sources

All URLs accessed 3 September 2026. Items marked *(secondary)* are not primary vendor
documentation and are flagged where they carry weight.

1. Apple, App Store Connect Help — *Create a new version* ("it's not possible to revert to a previous version on the App Store"; roles that may create a version) — https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version
2. Digia, *Staged Rollouts: How to Reduce Release Risk in Mobile Apps* (7-day 1/2/5/10/20/50/100% progression; 30 cumulative pause days; no binary rollback) — *(secondary)* — https://www.digia.tech/post/staged-rollouts-how-to-release-to-everyone-without-the-risk-of-everyone
3. Apple, *Xcode Cloud* overview and pricing (25 compute hours/month included; 100 h US$49.99, 250 h US$99.99, 1,000 h US$399.99, 10,000 h US$3,999.99) — https://developer.apple.com/xcode-cloud/
4. Apple, *Get started with Xcode Cloud* (roles that may configure workflows; subscription management) — https://developer.apple.com/xcode-cloud/get-started/
5. GitHub Docs, *GitHub Actions billing* (free for public repositories on standard runners; larger runners always billed; macOS $0.062/min, Linux $0.006/min; included minutes by plan) — https://docs.github.com/en/billing/concepts/product-billing/github-actions
6. GitHub, *Pricing changes for GitHub Actions* ("Actions will remain free for public repositories"; $0.002/min platform charge not applicable to public repositories; self-hosted quota change from 1 March 2026) — https://github.com/resources/insights/2026-pricing-changes-for-github-actions
7. GitHub Docs, *Actions runner pricing reference* (per-minute rates; larger runners not free for public repositories) — https://github.com/github/docs/blob/main/content/billing/reference/actions-runner-pricing.md
8. Apple, *Creating API Keys for App Store Connect API* (team vs individual keys; individual keys cannot use Provisioning endpoints, Sales and Finance, or `notarytool`) — https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api
9. Apple, App Store Connect Help — *App Store Connect API* (roles required to generate team and individual keys; revocation and the 30-day revoked list) — https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api
10. Apple, *Notarizing macOS software before distribution* (Developer ID certificate required; hardened runtime; App Store submission does not require notarisation; `notarytool` and `stapler` for automated systems) — https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
11. `notarytool(1)` man page (team vs individual keys; `--issuer` required for team keys and rejected for individual keys; `store-credentials` keychain profiles) — https://keith.github.io/xcode-man-pages/notarytool.1.html
12. Apple, *Signing Mac Software with Developer ID* (Gatekeeper; hardened runtime; `notarytool` replaced `altool` from November 2023) — https://developer.apple.com/developer-id/
13. Stack Overflow, *App Store Connect Upload Error: "You haven't been given access to cloud-managed distribution certificates"* (both *Access to Certificates, Identifiers & Profiles* and the child *Access to Cloud Managed Distribution Certificate* are required) — *(secondary)* — https://stackoverflow.com/questions/69609859/app-store-connect-upload-error-you-havent-been-given-access-to-cloud-managed-d
14. *How to enable "Access to Cloud Managed Developer ID Certificate" in App Store Connect?* (per Apple Developer Support: modifiable only by the Account Holder, and grantable only to Admins) — *(secondary; verify in App Store Connect before relying on it)* — https://exchangetuts.com/how-to-enable-access-to-cloud-managed-developer-id-certificate-in-app-store-connect-1766432403342454
15. Apple Developer, *Apple Developer Program roles* — https://developer.apple.com/help/account/access/roles
16. HACS, *Include default repositories* (submission process; HACS Action and hassfest must pass with no errors or ignores; full release required; automated review checks including brands, description, issues enabled and topics) — https://www.hacs.xyz/docs/publish/include/
17. HACS, *General* (`hacs.json` at the repository root; supported keys; release tag drives the remote version) — https://www.hacs.xyz/docs/publish/start/
18. HACS, *Integrations* (one integration per repository; `manifest.json` required keys; `brand/icon.png`) — https://www.hacs.xyz/docs/publish/integration/
19. `home-assistant/brands` — https://github.com/home-assistant/brands
20. `hacs/action` — https://github.com/hacs/action ; `home-assistant/actions` (hassfest) — https://github.com/home-assistant/actions
21. Grafana, *Share dashboards and panels* → *Publish a community dashboard* (Classic model export required; Grafana Cloud sign-in; My dashboards → Upload dashboard; Save and Publish, then Submit for metadata updates) — https://grafana.com/docs/grafana/latest/visualizations/dashboards/share-dashboards-panels/
22. `actions/attest-build-provenance` (SLSA build provenance in in-toto format; Sigstore public-good instance for public repositories; v4 wraps `actions/attest`) — https://github.com/actions/attest-build-provenance
23. GitHub Docs, *Using artifact attestations to establish provenance for builds* — https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations
24. GitHub CLI, `gh attestation verify` (`--signer-workflow`, `--deny-self-hosted-runners`, `--predicate-type`, offline verification via `--custom-trusted-root`) — https://cli.github.com/manual/gh_attestation_verify
25. `probot/dco` — DCO GitHub App (required status check; author-email matching; `@dcoapp recheck`) — https://github.com/probot/dco
26. GitHub Docs, *Managing the commit signoff policy for your repository* (compulsory sign-off applies only to web-interface commits) — https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/managing-the-commit-signoff-policy-for-your-repository
27. Developer Certificate of Origin 1.1 — https://developercertificate.org/
28. REUSE Specification v3.3 (`LICENSES/` naming; `REUSE.toml` schema version 1) — https://reuse.software/spec-3.3/
29. `fsfe/reuse-tool` (REUSE 3.3 compliance; `reuse lint`, `reuse spdx`, `lint-file`) — https://github.com/fsfe/reuse-tool
30. Arch Linux RFC 0052, *REUSE for package license linting* (a downstream packager adopting REUSE as a gate) — https://rfc.archlinux.page/0052-reuse/
31. `anchore/syft` — Swift Package Manager cataloger for `Package.resolved` versions 1, 2 and 3; multiple SBOM output formats — https://github.com/anchore/syft
32. Syft CLI reference (`-o spdx-json`, `-o cyclonedx-json`; cataloger selection) — https://oss.anchore.com/docs/reference/syft/cli/
33. Organization for Ethical Source, *Announcing Contributor Covenant 3.0* (released 28 July 2025) — https://ethicalsource.dev/blog/contributor-covenant-3/
34. Contributor Covenant 3.0 text — https://www.contributor-covenant.org/version/3/0/code_of_conduct/
35. OpenSSF, *Guide to implementing a coordinated vulnerability disclosure process for open source projects* (≤14-day initial response) — https://oss-vulnerability-guide.openssf.org/maintainer-guide.html
36. Apple Developer News, medical-device declaration requirement for Health & Fitness and Medical apps in the EEA, UK and US (from 26 March 2026) — https://developer.apple.com/news/?id=nyqbfz1y
37. Apple Developer, *DSA trader status required for apps in the EU* (since 17 February 2025) — https://developer.apple.com/news/upcoming-requirements/?id=02172025a
38. Apple, App Store Connect Help — *Manage European Union Digital Services Act trader requirements* (address, phone and email published; P.O. Box permitted for individuals) — https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements
39. Apple, App Review Guidelines (3.2.2(iv): apps raising funds must be free and may only collect funds outside the app) — https://developer.apple.com/app-store/review/guidelines/
40. GNU Affero General Public License v3.0 (§7 additional permissions; §13 permission to combine with GPLv3 work) — https://www.gnu.org/licenses/agpl-3.0.en.html
41. European Commission, draft guidance C(2026) 5252 final, 27 July 2026 — CRA guidance, §3 *Free and open-source software* (¶42, ¶47, ¶53, ¶61, ¶62, ¶63–65) — https://www.juridice.ro/wp-content/uploads/2026/07/C_2026_5252_1_EN_annexe_acte_autonome_cp_part1_v3_kXuCPwXXxAuG8Uj44Ar0o2Vros_131456.pdf
42. cyberresilienceact.eu, *CRA Reporting: 24h, 72h & 14-Day Deadlines (Article 14)* (applies 11 September 2026; not retroactive) — *(secondary)* — https://www.cyberresilienceact.eu/reporting.html
43. *CRA SBOM Requirements: Mandated, Optional, and Unclear* (Annex I Part II(1) top-level dependencies; technical documentation not publication; Article 13(24) implementing act not yet adopted) — *(secondary)* — https://cra-decoded.com/blog/posts/004_cra_sbom_requirements/
44. Pol Piella, *Safely pinning SPM dependencies to exact versions* (`Package.resolved` is not a conventional lockfile; `xcodebuild -disableAutomaticPackageResolution`) — *(secondary)* — https://www.polpiella.dev/safely-pinning-spm-depedencies-to-exact-versions
45. Swift Forums, *Toolchain Management / Hygiene in multi-toolchain / multi-sdk environments* (on Apple platforms the SDK always comes from the selected Xcode; Xcode and swift.org toolchains are always distinct builds; `.swift-version` with `swiftly`) — *(secondary; Swift core-team participation)* — https://forums.swift.org/t/toolchain-management-hygiene-in-multi-toolchain-multi-sdk-environments/88761
46. `swiftlang/swift-format` (in the Swift 6+ toolchain; `swift format lint --strict`) — https://github.com/swiftlang/swift-format
47. Apple, App Store Connect Help — *TestFlight overview* (100 internal testers, 10,000 external, Beta App Review, 90-day build expiry) — https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
48. Apple, App Store Connect Help — *Invite external testers* (public links, tester criteria, tester limit) — https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers
49. Model Trademark Guidelines (CC BY 3.0 template) — http://modeltrademarkguidelines.org/
50. Keep a Changelog 1.1.0 — https://keepachangelog.com/en/1.1.0/
51. Semantic Versioning 2.0.0 — https://semver.org/spec/v2.0.0.html
52. Apple Developer, *D-U-N-S Number* (legal entity required for organisation enrolment) — https://developer.apple.com/help/account/membership/D-U-N-S
53. XcodeGen — https://github.com/yonaskolb/XcodeGen ; Tuist — https://github.com/tuist/tuist
54. Apple, *Writing custom build scripts* for Xcode Cloud (`ci_post_clone.sh`, `ci_pre_xcodebuild.sh`, `ci_post_xcodebuild.sh`) — https://developer.apple.com/documentation/xcode/writing-custom-build-scripts
55. Xcode 26 Release Notes (Swift Package Manager and Swift Packages changes; new package PIF builder preview) — https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes

**Confidence notes.** Items 1, 3–12, 15–21, 23, 26–29, 34, 36–40, 47–48, 52, 54–55 are primary
vendor, standards-body or regulator sources. Items 2, 13, 14, 42–45 are secondary and are marked
in place; of these, **item 14 carries the most weight for the least evidence** — the claim that
*Access to Cloud Managed Developer ID Certificate* is Account-Holder-only and Admin-only rests
on a developer's report of an Apple Developer Support answer, and it determines whether R-105b
is satisfiable for the Mac target. It should be verified directly in App Store Connect during
the first month of the entity's enrolment, alongside the notarisation dry run.
