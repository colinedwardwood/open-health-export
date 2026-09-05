# Apple Platform / HealthKit Domain Expert — Stage 1 Contribution

> **Evidence labelling.** Every load-bearing claim below is tagged:
> **[D]** documented Apple behaviour (developer documentation, SDK headers, App Review Guidelines, WWDC, or an Apple DTS/Frameworks engineer answer on the developer forums);
> **[R]** widely reported real-world developer behaviour (not guaranteed by Apple, but consistently observed);
> **[I]** my own inference or judgement.
> Where I could not verify a current fact I say so explicitly rather than guessing.
>
> **Primary evidence advantage.** Several counts and quotations below come from the *installed SDK* rather than the web:
> `iPhoneOS26.5.sdk` inside Xcode 26.6 (`SDKSettings.plist` → `DisplayName = iOS 26.5`), headers at
> `…/iPhoneOS.sdk/System/Library/Frameworks/HealthKit.framework/Headers/`. That is the single most authoritative
> source available for "what does the current SDK actually expose" and I used it in preference to blog posts. [D]

---

## Executive summary

1. **HealthKit does not work on macOS. At all.** The framework links and the headers carry `macos(13.0)`
   availability annotations, but `HKHealthStore.isHealthDataAvailable()` returns `false` on macOS and Mac Catalyst,
   so no read or write is possible. Apple's documentation states this plainly, and a DTS engineer reconfirmed it in
   September 2025; a developer was still asking (unanswered) in March 2026. **The premise's "first-class support
   across iOS / iPadOS / macOS / watchOS" is not deliverable for macOS as a HealthKit client.** A Mac app can only
   ever be a *receiver* of data pushed from an iPhone or iPad, or an importer of files. [D] — Sources [1][2][3]
2. **"Automated export" on iOS is real but is *event-triggered and best-effort*, not scheduled.** `HKObserverQuery`
   plus `enableBackgroundDelivery` is the only mechanism that wakes a terminated app for health data changes. Apple
   documents that frequency is a *maximum*, that some types are silently capped at hourly, and a DTS engineer has
   stated on the record that "the delivery frequency is not guaranteed" and is subject to undocumented factors.
   `BGAppRefreshTask` is scheduled by the system, not by us, and gives ~30 seconds. There is **no API for "export
   every 15 minutes"**. [D] — Sources [4][5][19][17]
3. **A locked iPhone cannot be read.** The HealthKit store is in Data Protection class Complete Protection. The SDK
   defines `HKErrorDatabaseInaccessible` as *"Protected health data is inaccessible because the device is locked."*
   So a background wake that lands while the device is locked yields **nothing**. Writes are cached and merged on
   unlock; reads simply fail. This is the single largest constraint on "continuous automatic export". [D] — [6][31]
4. **App Review Guideline 5.1.3(ii) says apps "may not store personal health information in iCloud."** That is a
   flat prohibition, and the reference product advertises iCloud Drive as an export destination. Any CloudKit-based
   sync of health data, or any app-managed iCloud container holding health exports, is a rejection risk. This needs
   a PM decision, not an engineering workaround. [D] — Source [7]
5. **The metric count is not the differentiator.** The current SDK declares **120 quantity types, 70 category types
   (1 deprecated), 6 characteristics, 2 correlations, 2 scored assessments, 9 clinical record types, 1 document
   type**, plus ~10 further object/sample types that have no string identifier (workout, workout route, heartbeat
   series, activity summary, audiogram, ECG, vision prescription, state of mind, medication dose event, user
   annotated medication). Total distinct `HKObjectType`s ≈ **219**, of which ≈ **210** are reachable without the
   clinical-records entitlement. "150+" is comfortably beaten, but ~40 of the quantity types are dietary
   micronutrients and ~45 of the category types are symptom flags that most users have never recorded. **Claim
   completeness, not a number.** [D from SDK headers][31]

---

## What HealthKit actually exposes (coverage, with an honest metric count)

### Counted from the iOS 26.5 SDK headers [D]

| Family | Declared identifiers | Notes |
|---|---:|---|
| `HKQuantityTypeIdentifier` | **120** | Includes ~40 `Dietary*` micronutrients. Newest additions are cycling/rowing/skiing metrics (iOS 17–18) and workout effort scores (iOS 18). |
| `HKCategoryTypeIdentifier` | **70** (69 current + `audioExposureEvent` deprecated in iOS 14) | Includes ~45 symptom types, cycle-tracking types, `sleepAnalysis`, `mindfulSession`, `sleepApneaEvent` (iOS 18), `hypertensionEvent` (**iOS 26.2**). |
| `HKCharacteristicTypeIdentifier` | **6** | `activityMoveMode`, `biologicalSex`, `bloodType`, `dateOfBirth`, `fitzpatrickSkinType`, `wheelchairUse`. Not time series — single values, no anchored query. |
| `HKCorrelationTypeIdentifier` | **2** | `bloodPressure`, `food`. Containers over other samples; the components are also independently readable. |
| `HKScoredAssessmentTypeIdentifier` | **2** | `GAD7`, `PHQ9` (iOS 18). Mental-health questionnaire scores. |
| `HKClinicalTypeIdentifier` | **9** | `allergyRecord`, `clinicalNoteRecord`, `conditionRecord`, `coverageRecord`, `immunizationRecord`, `labResultRecord`, `medicationRecord`, `procedureRecord`, `vitalSignRecord`. **Entitlement-gated** — see next section. |
| `HKDocumentTypeIdentifier` | **1** | `CDA` (`HKCDADocumentSample`). |
| Object/sample types with no string identifier | **~10** | `HKWorkoutType`, `HKSeriesType.workoutRoute`, `HKSeriesType.heartbeatSeries`, `HKActivitySummaryType`, `HKAudiogramSampleType`, `HKElectrocardiogramType`, `HKPrescriptionType` (vision), `HKStateOfMindType` (iOS 18), `HKMedicationDoseEventType` (**iOS 26**), `HKUserAnnotatedMedicationType` (**iOS 26**). |
| `HKWorkoutActivityType` enum | **84 cases** (2 deprecated aliases + `Other`) | An *attribute of a workout*, not a separate readable type. Counting these as "metrics" would be dishonest. |
| `HKCategoryValueSleepAnalysis` | **7 values** | `inBed`, `awake`, `asleepUnspecified`, `asleepCore`, `asleepDeep`, `asleepREM`, plus deprecated `asleep`. Sleep *stages* are values on `sleepAnalysis` samples, not distinct types. |
| `HKUpdateFrequency` | **4 values** | `immediate`, `hourly`, `daily`, **`weekly`** — note `weekly` exists and is rarely mentioned. |

### How we should count, and what we should claim

Counting "metrics" is a marketing exercise with at least five defensible answers, and the reference product's
"150+" is not falsifiable because it does not state its method. [I] My recommendation:

- **Do not publish a headline number.** Publish a *machine-generated coverage matrix*, produced by enumerating the
  SDK at build time, listing every `HKObjectType` and whether we support it for export. That is falsifiable, it is
  self-updating, and it is a genuine OSS differentiator over a closed app's marketing copy. [I]
- If a number is required for parity messaging, the honest one is **"210+ distinct HealthKit data types, i.e. every
  non-clinical type the iOS 26 SDK exposes"** — and it must be produced by the enumeration test, not hand-counted.

### Notable coverage subtleties [D]

- **Workout routes** are `HKWorkoutRoute`, a series sample retrieved per workout via `HKWorkoutRouteQuery` — they
  are *not* returned by ordinary sample queries and are the natural source for GPX. Series samples must be streamed;
  a long ride can hold thousands of `CLLocation` points.
- **ECG** (`HKElectrocardiogram`) is **read-only** — you cannot request share authorisation and cannot write it.
  Individual voltage measurements come from a separate `HKElectrocardiogramQuery`, i.e. two round trips per sample,
  and each ECG is ~30 s of high-rate voltage data. Source [11]
- **Heartbeat series** (`HKHeartbeatSeriesSample`) similarly requires `HKHeartbeatSeriesQuery` for beat-to-beat data.
- **Audiograms** (`HKAudiogramSample`) carry sensitivity points, with clamping ranges added in recent SDKs.
- **State of Mind** (iOS 18) has valence, 7 valence classifications, **38 labels** and an associations enum — it is
  a structured record, not a scalar, and will not fit a naive "metric → number" export schema.
- **Medications (iOS 26) use a different authorisation model.** `HKUserAnnotatedMedicationType.requiresPerObjectAuthorization()`
  is true: the user authorises **each individual medication**, via `requestPerObjectReadAuthorization(for:predicate:)`.
  New medications added later prompt the user *inside the Health app*, per-app. Dose events
  (`HKMedicationDoseEvent`) are ordinary samples and are granted automatically alongside the medication.
  Apple's own WWDC25 session warns that dose events are "logged for days in the past, deleted and re-persisted when
  editing", which is a delta-sync hazard. Sources [15]
- **Vision prescriptions** (`HKVisionPrescription`, iOS 16) also use per-object authorisation.
- **Sleep score** (watchOS 26 / iOS 26) and **hypertension notifications** (FDA-cleared, watchOS 26) are user-facing
  features. `hypertensionEvent` is exposed as a category type from **iOS 26.2**. I could **not verify** that the
  numeric sleep score is exposed as a public HealthKit type — the SDK headers show no such identifier, and I found no
  Apple documentation for one. **Treat sleep score as not exportable until proven otherwise.** [D + explicit non-verification] — [40][31]
- **`HKVerifiableClinicalRecord`** (SMART Health Cards / EU DCC) exists but requires an explicit user-presented
  request flow per query and is not part of the ordinary store; I regard it as out of scope. [I]
- **Characteristics are a privacy asymmetry.** Date of birth, biological sex, blood type and skin type are static
  identity-adjacent attributes. Exporting them by default to a user-specified endpoint materially raises the
  re-identification risk of an otherwise pseudonymous dataset. [I]

---

## Restricted data categories and entitlements

### Entitlement inventory [D] — Sources [8][9][22]

| Entitlement | Value / type | How obtained | Needed by us? |
|---|---|---|---|
| `com.apple.developer.healthkit` | Boolean | Xcode capability checkbox; auto-registered on the App ID. **No Apple approval, no form.** | **Yes — mandatory.** |
| `com.apple.developer.healthkit.access` | Array of strings; the only documented value is `health-records` | Xcode nested "Clinical Health Records" checkbox. **No pre-approval form** — Apple gates it at App Review instead. Requires `NSHealthClinicalHealthRecordsShareUsageDescription` and a working privacy-policy URL that renders on the clinical permission sheet. | **Recommend Won't-have for v1.** |
| `com.apple.developer.healthkit.background-delivery` | Boolean | Xcode capability checkbox. **Mandatory since iOS 15 / watchOS 8** — without it `enableBackgroundDelivery` fails with `HKError.errorAuthorizationDenied`. No Apple approval. | **Yes — mandatory for any automation claim.** |
| `com.apple.developer.healthkit.recalibrate-estimates` | Boolean | Capability checkbox | No — write-side feature, irrelevant to export. |
| `com.apple.developer.health.fall-detection` | Boolean | **Requires an approval request to Apple** (`developer.apple.com/contact/request/fall-detection-api`) plus `NSFallDetectionUsageDescription`. Reported approval time 2–3 days; reported provisioning-support pitfalls that block TestFlight. | No — this is CoreMotion fall *notifications*, not the `numberOfTimesFallen` HealthKit quantity, which needs no entitlement. |

**The important, counter-intuitive finding: ECG, atrial fibrillation burden, sleep apnea events, hypertension
events, cycle tracking, sexual activity, pregnancy, mental wellbeing and medications all require *no special
entitlement*.** They are ordinary HealthKit types behind ordinary per-type user authorisation. The only
entitlement-gated *data* category is FHIR clinical records. [D] — [9][11]

### Clinical records: why I recommend excluding them from v1

1. The gate is App Review judgement, not a form. There is no way to de-risk it in advance, and a rejection on
   5.1.3 grounds attaches to the whole submission, not just the feature. [D][7][10]
2. Clinical records are read-only FHIR JSON from named healthcare institutions. Redistributing a hospital's FHIR
   resources to a user-specified arbitrary endpoint is the *worst possible* framing to put in front of a reviewer
   for an app whose entire purpose is shipping data off-device. [I]
3. `NSHealthRequiredReadAuthorizationTypeIdentifiers` requires **three or more** clinical types if used at all, and
   an all-or-nothing denial returns `HKErrorRequiredAuthorizationDenied` without telling you which type failed. [D][23]
4. Cost/benefit: 9 of ~219 types, available only to users of participating institutions, in exchange for putting
   the entire App Store listing at elevated risk. [I]

**Honest version of the promise:** "Every health and fitness type Apple exposes. Clinical records (FHIR documents
from your healthcare provider) are deliberately out of scope — export them from the Health app instead."

---

## Background execution: what "automatic" can honestly mean

### The only mechanism that wakes a terminated app for health data

`HKObserverQuery` + `HKHealthStore.enableBackgroundDelivery(for:frequency:)`. Documented behaviour [D] — [4][5]:

- The system wakes the app **when a process saves or deletes samples of the specified type**, at most once per the
  frequency period. Frequency is a **ceiling, not a schedule**.
- **Some types are silently capped at hourly.** Apple names `stepCount` on iOS explicitly: "the `updateHandler` will
  be triggered at most once per hour, even if you use `enableBackgroundDelivery` + `.immediate`" (DTS, forum 823699).
  Apple does **not** publish the full list of capped types on iOS. I could not find one; **we must discover it
  empirically and document what we find.**
- **On watchOS, most types are capped at hourly.** Apple documents exactly ten exceptions that can be `.immediate`:
  `highHeartRateEvent`, `lowHeartRateEvent`, `irregularHeartRhythmEvent`, `environmentalAudioExposureEvent`,
  `headphoneAudioExposureEvent`, `lowCardioFitnessEvent`, `numberOfTimesFallen`, `vo2Max`, `handwashingEvent`,
  `toothbrushingEvent`. Note that **`heartRate` and `stepCount` are not on that list.**
- **watchOS wake budget is documented and small:** background HealthKit updates share a budget with
  `WKApplicationRefreshBackgroundTask`, giving **four updates per hour, and only if the app has a complication on
  the active watch face.**
- Observer queries must be installed in `application(_:didFinishLaunchingWithOptions:)` so they exist before
  HealthKit delivers.
- **You must call the completion handler.** Three failures and HealthKit stops delivering to your app entirely,
  after an exponential backoff.
- **Background delivery does not work in the Simulator.** All verification must be on device.

### What Apple's own engineers say about reliability [D] — [19][20][21]

- "No, the delivery frequency is not guaranteed. The system tries to honor the specified frequency, but may not
  achieve that due to the app's background execution time budget and **other undocumented factors, and there is no
  API to change the behavior**." (DTS, forum 823699.)
- iOS has a background execution time budget, "but isn't as strict as watchOS"; delivery quality depends on
  remaining budget, battery level, and contention with other apps. DTS recommends testing at **80%+ battery**.
- A developer reported identical builds getting ~8–16 minute delivery on some devices and ~hourly on others, with
  no configuration difference. Apple's answer was about complications and battery, not a fix. (forum 814914.)
- On a 2026 thread where background delivery worked under Xcode but never on a disconnected device, DTS's two
  diagnostic questions were: is the completion handler called on **all** code paths, and **"is the app force quitted
  when testing?"** — which is Apple confirming force-quit as a first-class cause. (forum 823318, Apr 2026.)

### Device lock — the hard ceiling [D] — [6][31]

- Apple: "the device encrypts the HealthKit store when the user locks the device. As a result, **your app may not be
  able to read data from the store when it runs in the background.** However, your app can still write to the store,
  even when the phone is locked."
- The SDK names the failure: `HKErrorDatabaseInaccessible` = *"Protected health data is inaccessible because the
  device is locked."*
- Apple's platform security documentation places the health database in Data Protection class **Complete
  Protection** (accessible only after passcode/biometric unlock), with a separate operational database at
  *Protected Until First User Authentication* holding the access tables and **the scheduling information used to
  launch apps when new data is available** — which is precisely why the wake can fire while the read cannot succeed.
  (The version of this text I could retrieve is the 2015 iOS Security white paper; the *mechanism* is corroborated
  by the current HealthKit privacy documentation and by the error constant, so I treat the mechanism as [D] and the
  exact class names as [D, older source].) — [35]

**Consequence:** for a user who keeps their phone locked, background wakes are largely wasted. Real export happens
opportunistically when the device is unlocked. Nothing we build changes this.

### Network I/O when woken

- Network access **is** permitted in a background wake; there is no HealthKit-specific prohibition. [D by absence]
- The practical envelope is small. Apple documents ~**30 seconds** for `BGAppRefreshTask`, background push, and
  `beginBackgroundTask` assertions in modern iOS. [D][17][R for the 30 s figure applied to observer wakes]
- The correct escape hatch is a **background `URLSession`**: transfers are performed by the system outside the app
  process and survive suspension and termination, with the app relaunched on completion. This is the only way to
  honestly promise "large exports complete". [D][17]
- I could **not find** an Apple-documented figure for the wake duration granted specifically to an
  `HKObserverQuery` background launch. Treat "tens of seconds" as [R] and design for it, do not quote it.

### `BGTaskScheduler`, and its three shapes [D] — [16][17][18]

| API | Who starts it | Budget | Suitable for us? |
|---|---|---|---|
| `BGAppRefreshTask` | **System decides**, learned from user launch patterns | ~30 s | As a *belt-and-braces* catch-up sweep only. Cannot be relied on for a schedule. |
| `BGProcessingTask` | System, typically when device is idle/charging | Minutes; killed if the user returns | Good for a large historical backfill *if and when* the system grants it. Not promisable. |
| `BGContinuedProcessingTask` (**new in iOS 26**) | **Explicit user action only** — button or gesture | Continues the running job, with a **system-provided progress UI the user can cancel**; priority boosted on return | **This is the right API for user-initiated bulk export**, and it is a genuine iOS 26-era win: "export my whole history" can survive backgrounding with visible progress. Apple is explicit that it is **not** for silent maintenance, auto-sync, or backups, and "the system is designed to reject that usage". Background GPU access exists but is currently iPad-with-M3-or-newer only (irrelevant to us). |

### User- and system-controlled kill switches

| Factor | Effect | Evidence |
|---|---|---|
| **Force-quit** (swipe up from App Switcher) | Suppresses background launches until the user manually opens the app again. Apple DTS treats this as a standard cause of "background delivery never fires". Note the older StackOverflow claim that HealthKit *does* relaunch after force-quit is from iOS 8.1 and is contradicted by current DTS guidance. | [D] (DTS, forum 823318) |
| **Background App Refresh** toggled off (per-app or globally) | Developer consensus and Apple's own test-configuration checklists treat it as required. I could **not** find an unambiguous Apple statement on whether HealthKit background delivery specifically survives it. **Flagging as unverified — we must test it.** | [R] + explicit non-verification |
| **Low Power Mode** | Reduces/suspends background activity. No HealthKit-specific documentation of the interaction; DTS asks testers to disable it. | [R] |
| **Low battery** | DTS explicitly recommends 80%+ battery for reliable testing, i.e. delivery degrades with battery. | [D] (forum 814914) |
| **Guest User mode** (visionOS/shared devices) | `HKErrorNotPermissibleForGuestUserMode`; authorisation sheets fail silently. | [D][31][12] |
| **MDM / enterprise restriction** | `HKErrorHealthDataRestricted`; HealthKit can be disabled by profile. | [D][31][1] |
| **Authorisation revoked** | Reads silently return empty. **Apple deliberately makes read-denial indistinguishable from no-data**, so we can *never* tell the user "you denied heart rate" with certainty. | [D][6] |

### What we may honestly promise

**Say this:**
> "When new health data is written, iOS wakes the app and it exports the delta. In practice this happens within
> minutes to an hour of the data appearing, whenever the device is unlocked and has background budget available.
> Some types — step count on iPhone, and most types on Apple Watch — are capped by iOS at one wake per hour. If you
> force-quit the app or disable Background App Refresh, automatic export stops until you open it again. Nothing on
> iOS can export while the device is locked."

**Do not say:** "real-time", "continuous", "every N minutes", "runs in the background 24/7", or "works even if you
never open the app". [I]

**macOS is the honest exception:** a Mac app is not sandboxed into the iOS background model, can run a
`LaunchAgent`/login item, and can hold a long-lived process. But it has no HealthKit. So the *one* platform where we
could genuinely offer scheduled automation is the one platform with no data to automate. [I]

---

## Platform matrix

| Capability | iOS 26 | iPadOS 26 | macOS 26 | watchOS 26 |
|---|---|---|---|---|
| HealthKit framework links | Yes | Yes | Yes (headers annotate `macos(13.0)`) | Yes |
| `isHealthDataAvailable()` | **true** | **true (iPadOS 17+ only)** | **false — always** | **true** |
| Can read/write health data | Yes | Yes | **No** | Yes |
| `HKObserverQuery` + `enableBackgroundDelivery` | Yes (entitlement required) | Yes | N/A | Yes, **4 wakes/hour, complication required** |
| `.immediate` frequency honoured | Best-effort; some types capped hourly (`stepCount` documented) | As iOS | N/A | **Only 10 documented event types**; most capped hourly |
| `BGTaskScheduler` (`BGAppRefreshTask` / `BGProcessingTask`) | Yes | Yes | Different model (`NSBackgroundActivityScheduler`, login items) | `WKApplicationRefreshBackgroundTask`, shared budget |
| `BGContinuedProcessingTask` (iOS 26) | Yes | Yes (GPU variant needs M3 iPad) | N/A | No |
| Store readable while device locked | **No** | **No** | N/A | Watch unlock semantics differ; **unverified** |
| Clinical records (`health-records`) | Yes with entitlement | Yes with entitlement | No | Not a clinical-records surface |
| Medications (iOS 26, per-object auth) | Yes | Yes | No | Read available per headers; UI is iPhone-centric |
| Workout routes / GPX source | Yes | Yes | No | Yes (route builder) |
| Files app / document picker export destination | Yes | Yes | Yes (full FS with user consent) | No |
| Long-lived / scheduled local process | No | No | **Yes** | No |
| Distribution channels | App Store, TestFlight, EU alt-marketplace/Web Distribution | Same | Mac App Store, **notarised direct download**, TestFlight | Bundled with the iOS app |

**Key asymmetry:** the two platforms with the most permissive background execution (macOS) and the most data
(watchOS) are respectively the one with no HealthKit and the one with the tightest wake budget. [I]

### Legitimate routes to get data onto a Mac

Since a Mac cannot read HealthKit, these are the only options [I, informed by [3]]:

1. **iPhone/iPad pushes to the Mac over the local network.** The Mac runs a listener (HTTP or similar); the iOS app
   is the source of truth. This is what the reference product does with its TCP server. Requires local network
   permission on iOS and is subject to all the background constraints above.
2. **iOS app writes files; the user moves them.** Files app / AirDrop / document picker into a user-chosen folder.
   Fully within the rules and needs no network.
3. **iOS app pushes to a self-hosted endpoint the Mac also reads.** The Mac becomes a client of the user's own
   server, not of HealthKit.
4. **Manual Health-app export.** The user's own "Export All Health Data" produces a zip with `export.xml`, a
   `*_cda.xml` and a `workout-routes/` folder of GPX. A Mac app can import this. It is manual, one-shot and huge,
   but it is the only route that requires no iOS app at all.
5. **Shared iCloud container.** Technically available; **directly in tension with Guideline 5.1.3(ii)** ("may not
   store personal health information in iCloud"). Do not design around it without a PM ruling.

Running the iOS app on an Apple Silicon Mac, or Mac Catalyst, **does not help** — `isHealthDataAvailable()` is false
in both cases. [D][1][2]

---

## App Review and privacy obligations

Guidelines cited from the version last updated **8 June 2026**. [D][7]

### Mandatory configuration [D][8][24]

- `NSHealthShareUsageDescription` — required to read. Purpose strings are an explicit **App Store requirement** for
  any app integrating HealthKit, and they are shown to the user with the type list.
- `NSHealthUpdateUsageDescription` — required to write. If v1 is read-only, we should **omit** it and not request
  share authorisation at all; that is both honest and a smaller review surface. [I]
- `NSHealthClinicalHealthRecordsShareUsageDescription` — only if clinical records are in scope.
- Privacy policy URL in App Store Connect **and** reachable in-app. A privacy policy URL that fails to load is a
  reported instant rejection. [R]
- `healthkit` in `UIRequiredDeviceCapabilities` only if the app is useless without it (this excludes non-HealthKit
  iPads); Apple notes it is unused by watchOS apps.

### The guidelines that actually bind us

| Guideline | Text that matters | Consequence for us |
|---|---|---|
| **5.1.3(i)** | May not use or disclose health data to third parties "for advertising, marketing, or other use-based data mining purposes other than improving health management, or for the purpose of health research, and then only with permission." **"You must disclose the specific health data that you are collecting from the device."** | We must enumerate, in the listing and in-app, exactly which types we read. Our per-type opt-in UI is the compliance artefact. |
| **5.1.3(ii)** | "Apps must not write false or inaccurate data into HealthKit … and **may not store personal health information in iCloud.**" | **Blocks CloudKit sync of health data and app-managed iCloud storage of exports.** Also blocks any "backup your export to iCloud" feature. Whether a *user-initiated save into their own iCloud Drive via the document picker* counts is genuinely ambiguous — the reference product ships iCloud Drive export, which is evidence Apple has tolerated it, but that is not a rule. **PM decision required.** |
| **5.1.2(vi)** | HealthKit, Clinical Health Records, MovementDisorder, ClassKit and depth/face data "may not be used for marketing, advertising or use-based data mining, **including by third parties**." | "Including by third parties" reaches our *destinations*. If we shipped a preset integration with an ad-adjacent service we would own that. Argues for generic, user-configured endpoints and no bundled commercial presets. |
| **5.1.2(i)** | Must disclose where personal data is shared with third parties, **"including with third-party AI"**, and obtain explicit permission first. | Any LLM/AI feature touching health data needs its own consent gate. Relevant to future scope. |
| **2.5.1** | "HealthKit should be used for health and fitness purposes and **integrate with the Health app**." | We must be a visible, legitimate Health-app citizen. Reported rejection pattern: declaring HealthKit without substantial health functionality. Our app *is* health functionality, but "it's a data pipe" is a weaker story than "it's a health data manager with charts you can see". Argues for a real in-app data browser, not just a config screen. |
| **2.5.4** | Multitasking apps may only use background services for their intended purposes. | Our background modes must map to genuine export work. Do not declare unused modes. |
| **1.6 / 5.1.1(i)** | Appropriate security measures; privacy policy must state collection, retention/deletion, and how to revoke consent. | TLS on every destination; a documented deletion/revocation path. |
| **5.1.1(ix)** | Apps that "provide services in highly regulated fields (such as … healthcare) … **should be submitted by a legal entity that provides the services, and not by an individual developer.**" | **Live risk for an OSS project published by an individual.** My reading is that an export utility does not "provide healthcare services", so it should not bite — but this guideline is the one I would expect an unlucky reviewer to reach for. [I] **PM should decide whether to publish under an organisation account.** |
| **2.3.1(a)** | No hidden or undocumented features; all new features must be described **with specificity** in Notes for Review. | An app with a built-in TCP/HTTP server and arbitrary outbound endpoints *must* be explained pre-emptively in review notes, with a demo endpoint the reviewer can actually exercise. |
| **2.5.2** | Apps may not download, install or execute code that changes functionality. | Constrains any "user-supplied transform/template" idea. A declarative mapping format is fine; an embedded scripting engine is not. [I] |

### Known HealthKit rejection patterns

Reported, not Apple-published — treat as [R], though they are consistent across multiple independent write-ups [R]:

1. **Requesting types the app visibly doesn't use.** The most frequently cited cause. This is a direct problem for
   us: an app whose selling point is "all 210 types" requests, by design, everything. **Mitigation: never request
   the full set up front. Request only the types the user has enabled for export, at the moment they enable them.**
   This is the single most important review-risk mitigation in this document. [I]
2. Generic purpose strings ("We need your health data").
3. HealthKit data used for advertising/marketing/analytics.
4. HealthKit capability without substantial health functionality.
5. Missing or unreachable privacy policy; missing health-specific privacy policy content.
6. No in-app consent flow distinct from the HealthKit sheet when data goes to a third party.
7. No data-deletion path.

### Does shipping user data to arbitrary endpoints attract extra scrutiny?

I found **no Apple guideline that prohibits it**, and no guideline that names user-configured endpoints. Nothing in
5.1.3 forbids the user sending their own health data to their own server; 5.1.3(i) forbids *our* use and *disclosure
to third parties* for advertising/mining. The user's own self-hosted server is arguably not a "third party" at all. [I]

But: [R/I]

- Guideline 5.1.2(i)'s "clearly disclose where personal data will be shared with third parties" plus 5.1.3(i)'s
  "you must disclose the specific health data that you are collecting" together mean a reviewer will expect an
  explicit, per-destination consent surface.
- A reviewer cannot see where a user-configured endpoint points. That opacity is what generates scrutiny. The
  countermeasure is to make the app *self-evidently* user-controlled: no default endpoint, no vendor endpoint, no
  telemetry-by-default, a visible destination list, a visible log of what was sent where, and review notes that say
  so with a demo endpoint attached.
- **This is where the brief's OpenTelemetry differentiator becomes an App Review problem, not just a privacy one.**
  Any default-on outbound telemetry from a HealthKit app risks reading as undisclosed third-party sharing under
  5.1.2(i)/5.1.3(i). Telemetry must be **off by default, user-configured destination only, never a project-owned
  collector, and must never carry health sample values**. I would make that a hard requirement, not a preference.

---

## Distribution options and their trade-offs

| Channel | HealthKit works? | Reach | Cost/effort | Verdict for an OSS project |
|---|---|---|---|---|
| **iOS App Store** | Yes | Everyone | $99/yr + App Review per release + 5.1.3 exposure | **The only channel that reaches ordinary users.** Must be sustained. |
| **TestFlight** | Yes | ≤100 internal (App Store Connect users), ≤10,000 external; **builds expire at 90 days**; first build of each version needs Beta App Review (typically <24 h, no SLA); max 6 review submissions/24 h | Same $99/yr; a fresh build at least every 90 days forever | Viable for a beta cohort, **not** a distribution strategy: the 90-day expiry is a permanent treadmill and expired builds lose local data. |
| **macOS: notarised direct download** | **Irrelevant — no HealthKit on macOS** | Anyone | Developer ID cert + notarisation | Fine for a Mac *companion/importer*. Avoids Mac App Store sandbox constraints (2.4.5) and gives us full filesystem and long-lived process. Recommended for the Mac side. |
| **Mac App Store** | Irrelevant | Mac users | App Review + 2.4.5 constraints: sandboxing, no auto-launch without consent, updates only via MAS | Only if we want discoverability on the Mac; the 2.4.5(iii) "may not auto-launch … without consent" rule constrains a background sync agent. |
| **EU alternative app marketplace / Web Distribution** | Yes in principle — Notarization is a narrower review than App Review | EU only | **Authorisation from Apple required.** Under the terms effective 1 Oct 2026, eligibility requires one of: moderate D&B financial-stability score, publicly traded (or owned by), venture funding from an established firm, a completed financial audit by a licensed accountant, or being a government/education/nonprofit entity. 5% Core Technology Commission. | **An individual OSS maintainer meets none of these criteria** unless they incorporate as a nonprofit. Realistically unavailable. Also EU-only, so it cannot replace the App Store. |
| **AltStore / SideStore / Sideloadly (free Apple ID re-sign)** | **Reported: no.** Re-signing with a personal team does not register the HealthKit App ID feature, so the entitlement is stripped: the framework links, `requestAuthorization` never presents a sheet, and the app never appears under Settings → Health → Data Access. An open AltStore PR (#1762, Jul 2026) exists specifically to fix this and was closed as a draft. | Enthusiasts | Free | **Not viable.** I could not find an authoritative Apple statement on whether HealthKit is available under free provisioning generally; the *sideloader re-sign* case is well attested as broken. Flagging the general free-provisioning question as **unverified**. |
| **Build from source in Xcode with your own account** | Yes (with a Developer Program account) | Developers only | User needs Xcode + an account | Genuine and important for an OSS audit story. Not a consumer channel. 7-day expiry on free-account installs. |

**No channel relaxes the HealthKit entitlement rules.** The entitlement is a capability, not an approval, on every
channel; what varies is *how much review the app receives*, and only the EU channels reduce it — and those are
gated behind corporate eligibility criteria and are EU-only. [D][27][28]

**Recommendation [I]:** App Store as the primary iOS/iPadOS/watchOS channel, notarised direct download for the Mac
companion, build-from-source for auditors, TestFlight for betas only. Budget for the App Store treadmill (annual
fee, review per release, 5.1.3 exposure) as an explicit ongoing project cost — an OSS project that cannot sustain
it will strand its users.

---

## Data volume and performance envelope

### Realistic volumes

- A documented real case: an Apple Watch user since 2018 exported **~8 million `Record` rows** from the Health app,
  with heart-rate-style samples recorded every 30–90 s during any activity. [D — first-hand published account][30]
- Independently reported: **~2.9 GB `export.xml` for ~11 years** of data; **~790k heart-rate records** in a
  just-under-1 GB export; "a few months of heart rate quickly turns into hundreds of thousands of samples". [R][30]
- Order-of-magnitude planning figures I would design against [I]:
  - Heart rate alone: **10³–10⁴ samples/day** for an all-day Watch wearer → **1–4M samples over 5 years**.
  - Total store for a long-term Watch user: **5–20M samples**, with high-cardinality types (heart rate, HRV, energy,
    step count, audio exposure) dominating and 100+ types contributing almost nothing.
  - Workout routes: **10²–10⁴ locations per workout**; hundreds of workouts per year.
  - ECG: ~30 s of high-rate voltage per sample, fetched via a second query per sample.

### Delta sync semantics [D][13][14][15]

- `HKAnchoredObjectQuery` is the correct primitive. Give `nil` for the first run (full snapshot) and persist the
  returned `HKQueryAnchor` for every subsequent run. Apple's own guidance (WWDC25): anchored queries are "in general
  more efficient than setting up a paired observer query and a sample query".
- **Deletions are first-class.** The results handler returns `[HKDeletedObject]` (UUID + optional metadata) alongside
  additions. **You cannot detect deletions any other way** — a timestamp-based sync will silently accumulate
  records the user deleted. Any export format we define must be able to express a deletion.
- **Anchors are per-type-and-predicate.** Change the predicate and the anchor's meaning changes. Anchor state is
  therefore a per-type, per-destination concern.
- **Updates arrive as delete-then-add.** Apple warns explicitly for medication dose events that samples "may be
  logged for days in the past, deleted and re-persisted when editing", so an anchored update "may contain deletes
  for samples your app already processed". **A destination that only ever appends will drift out of sync.**
- Anchored queries stop when the app stops: their `updateHandler` only runs while the app is alive. Background
  continuity requires the observer query to relaunch us and re-run the anchored query.
- `HKQueryAnchor` is `NSSecureCoding`; anchors are opaque and must be persisted, versioned, and invalidated when the
  user changes type selection. [I]

### Performance envelope — falsifiable targets I propose [I]

Assumptions: iPhone 13 or newer, device unlocked, app in foreground for backfill; anchored delta in a background
wake. These are targets for Stage 4 to verify on device, not measurements.

- Initial full backfill of a 5M-sample store must complete **without the app being killed for memory**, using
  chunked anchored queries with a bounded `limit`, streaming serialisation, and never holding more than
  **N samples resident at once** (N to be tuned; ≤50k is my starting guess).
- A delta of **10,000 samples across ≤10 types serialises and hands off to a background `URLSession` in ≤5 s**.
- A single background wake must reach a **durable, resumable checkpoint within 10 s**, so that termination at any
  point loses no more than one chunk.
- Peak resident memory during any export **≤150 MB** (iOS background jetsam limits are lower than foreground and
  are not publicly specified; this is a conservative target). [I]
- Workout GPX export of a 4-hour ride (≈15k locations) completes in **≤3 s** and streams to disk rather than
  building the document in memory.

---

## Requirements I own

| ID | Requirement | Priority | Rationale | How we verify |
|---|---|---|---|---|
| HK-01 | The app MUST call `HKHealthStore.isHealthDataAvailable()` before any HealthKit call and present an explicit, non-error "not supported on this device" state. | Must | Mandatory on iPadOS ≤16 and **always false on macOS**. Apple documents this as a required check. [1] | Unit test with the check stubbed; manual run on macOS target and on an iPad simulator at iPadOS 16. |
| HK-02 | The macOS app MUST NOT claim to read Apple Health. Its role is receiver/importer/viewer only, and the UI and README must say so. | Must | HealthKit is non-functional on macOS. [1][2][3] | Code review: no HealthKit read paths compiled into the macOS target. Documentation review. |
| HK-03 | Type coverage MUST be generated by enumerating the SDK, not hand-maintained, and published as a coverage matrix. | Must | 219 types across 8 families, changing every OS release (e.g. `hypertensionEvent` in iOS 26.2). A hand list will rot. [31] | A test that enumerates all `HK*TypeIdentifier` values and fails if any is neither supported nor explicitly listed as excluded-with-reason. |
| HK-04 | Marketing and docs MUST NOT publish a bare "N metrics" figure. Coverage claims MUST be traceable to the generated matrix. | Should | "150+" is unfalsifiable marketing; our credibility differentiator is auditability. | Docs review; the number in any claim must be produced by the HK-03 test. |
| HK-05 | The app MUST request read authorisation **only** for types the user has enabled, at the point of enabling, and MUST NOT request the full type set. | Must | The most frequently reported HealthKit rejection cause is requesting unused types; Guideline 5.1.1(iii) data minimisation. [7][R] | Instrumented test asserting the requested type set equals the user-enabled set. Manual review of the permission sheet. |
| HK-06 | The app MUST NOT request share (write) authorisation in v1. `NSHealthUpdateUsageDescription` MUST be absent. | Should | Read-only is a smaller review and trust surface and matches the product's purpose. | Info.plist assertion test; no `save`/`requestAuthorization(toShare:)` calls in the codebase. |
| HK-07 | Purpose strings MUST be specific about what is read and where it can go, not generic. | Must | App Store requirement; generic strings are a reported rejection cause. [8] | Review checklist; screenshot of the permission sheet in QA artefacts. |
| HK-08 | Clinical records (`com.apple.developer.healthkit.access` = `health-records`) are **out of scope**, and the entitlement MUST NOT be present in the shipping build. | Won't (v1) | App-Review-gated with no pre-approval; 9 of ~219 types; worst-case framing for an app that ships data off-device. [9][10] | Entitlements assertion in CI. |
| HK-09 | The app MUST declare `com.apple.developer.healthkit.background-delivery` and MUST degrade gracefully to manual/foreground export if `enableBackgroundDelivery` fails. | Must | Mandatory since iOS 15; failure yields `errorAuthorizationDenied`. [4] | Fault-injection test forcing the failure; on-device check that the entitlement is in the provisioning profile for TestFlight and release builds. |
| HK-10 | Automation MUST be built on `HKObserverQuery` + `enableBackgroundDelivery`, with observer queries installed during app launch (including background launches). | Must | It is the only mechanism that wakes a terminated app for health data. Apple documents launch-time installation as required. [4][5] | On-device test: force-terminate via debugger detach, write a sample from the Health app, assert a background export occurs. |
| HK-11 | Every observer-query update handler MUST call its completion handler on **all** code paths, including error paths, within the wake window. | Must | Three failures and HealthKit permanently stops delivering. DTS's first diagnostic question. [4][21] | Static check that every exit path calls the handler; a soak test asserting delivery still works after ≥3 induced handler errors. |
| HK-12 | The app MUST treat `HKErrorDatabaseInaccessible` (device locked) as an expected, non-error outcome: checkpoint, do not consume the anchor, do not surface an alarm, retry on unlock. | Must | The store is encrypted while locked; a wake can fire when a read cannot succeed. [6][31] | Test with the device locked: assert no anchor advance, no user-visible error, and a successful export after unlock. |
| HK-13 | The app MUST NOT claim real-time, continuous, or fixed-interval automatic export anywhere in UI, App Store copy, or docs. It MUST state the honest constraints (hourly caps, lock, force-quit, Background App Refresh, Low Power Mode). | Must | Frequency is a documented ceiling; DTS states delivery is not guaranteed and depends on undocumented factors. [4][19] | Copy review against a banned-phrase list. A user-facing "why hasn't my export run?" explainer screen. |
| HK-14 | The app MUST surface per-destination export status: last successful export, last attempt, sample counts, and the reason for the most recent failure. | Must | The user cannot otherwise distinguish "iOS hasn't woken us" from "the endpoint is down". This is the honest substitute for a reliability guarantee. | UI test asserting each state renders; QA scenarios for each failure class. |
| HK-15 | Delta sync MUST use `HKAnchoredObjectQuery` with persisted per-type anchors. Timestamp-based sync is forbidden. | Must | Only anchored queries report deletions. [13][14] | Test: delete a previously exported sample in the Health app; assert the deletion is detected and emitted. |
| HK-16 | The export format MUST be able to express a **deletion** and an **update** (delete + re-add), and destinations MUST be able to apply them. | Must | Apple documents that updates arrive as delete-then-add and that deletes may cover already-processed samples. [14][15] | Round-trip test: add, edit, delete a sample; assert the destination's final state matches HealthKit exactly. |
| HK-17 | Bulk historical backfill MUST be chunked, resumable, and checkpointed, and MUST NOT hold the full result set in memory. | Must | 5–20M samples is a realistic long-term store. [30] | Synthetic 5M-sample store; assert completion, bounded peak memory, and correct resumption after forced termination mid-run. |
| HK-18 | Network transfer of export payloads MUST use a background `URLSession` so transfers survive suspension and termination. | Must | The background wake budget is ~tens of seconds; only background sessions run beyond it. [17] | On-device test: begin a large upload, background and terminate the app, assert completion and relaunch handling. |
| HK-19 | User-initiated bulk export SHOULD use `BGContinuedProcessingTask` (iOS 26+) with real progress reporting and cancellation. | Should | Purpose-built for exactly this shape of work, with a system progress UI the user can cancel. [16] | On-device test on iOS 26: start an export, background the app, assert the system progress UI appears, progresses, and cancels cleanly. |
| HK-20 | `BGAppRefreshTask` / `BGProcessingTask` MAY be used only as an opportunistic catch-up sweep, never as the basis of a schedule promise. | Could | The system, not the app, decides when these run. [17][18] | Design review; copy review to ensure no schedule is implied. |
| HK-21 | The app MUST NOT store health data or exports in an app-managed iCloud container, and MUST NOT use CloudKit to sync health data. | Must | Guideline 5.1.3(ii): "may not store personal health information in iCloud." [7] | Entitlements/code review: no CloudKit, no `NSUbiquitousContainers` holding health data. |
| HK-22 | Whether "save to the user's own iCloud Drive via the document picker" is offered is a **PM decision** and must be recorded as an ADR with the 5.1.3(ii) risk stated. | Must | Genuinely ambiguous; the reference product does it, but that is tolerance, not permission. | ADR exists and is referenced from the requirement. |
| HK-23 | The app MUST ship no default, vendor-owned, or pre-configured export destination. Every destination is user-created. | Must | Removes any reading of "app discloses health data to a third party" under 5.1.2(i)/5.1.3(i). [7] | Fresh-install test: destination list is empty; no outbound request occurs before the user creates a destination. |
| HK-24 | Observability/telemetry MUST be off by default, MUST target only a user-configured destination, MUST never be a project-owned collector, and MUST never carry health sample values or characteristics. | Must | Default-on outbound telemetry from a HealthKit app risks reading as undisclosed third-party sharing; 5.1.2(vi) reaches third parties. [7] | Network test on a fresh install: zero outbound bytes until configured. Redaction test asserting no sample values or characteristic data in any span or log. |
| HK-25 | All export destinations MUST use TLS by default. Plaintext HTTP MUST require an explicit, per-destination, informed opt-in for local-network use. | Must | Guideline 1.6 data security; health data in transit. [7] | Test that HTTP is rejected without the opt-in flag; ATS configuration review. |
| HK-26 | The app MUST provide an in-app path to stop all export, delete all locally cached health data and anchors, and revoke destinations — and the privacy policy MUST describe it. | Must | Guideline 5.1.1(i) requires retention/deletion and consent-revocation disclosure; reported rejection cause. [7] | UI test asserting local store and anchors are empty afterwards. |
| HK-27 | The app MUST include a genuine in-app health data browser, not merely a configuration screen. | Should | Guideline 2.5.1 requires HealthKit be used for health purposes and integrate with the Health app; "HealthKit capability without substantial health functionality" is a reported rejection cause. [7][R] | Product review against the guideline; the reviewer must be able to see health data in the app. |
| HK-28 | Read denial MUST be presented as "no data available" and never as a definitive "you denied this type". | Must | Apple deliberately makes read denial indistinguishable from an empty store; claiming otherwise misleads the user. [6] | Test with authorisation denied for one type: assert the copy does not assert denial. |
| HK-29 | Medications (iOS 26) MUST use `requestPerObjectReadAuthorization(for:)`, MUST handle newly authorised medications appearing without app involvement, and MUST NOT assume dose events are append-only. | Should | Documented per-object model; Apple warns dose events are retro-logged, edited and re-persisted. [15] | On-device test: authorise one of two medications, assert only that one is visible; retro-log and edit a dose, assert correct delta. |
| HK-30 | Characteristics (date of birth, biological sex, blood type, Fitzpatrick skin type, wheelchair use) MUST be off by default and flagged in the UI as re-identifying. | Should | Static identity-adjacent attributes materially raise re-identification risk in an otherwise pseudonymous export. [I] | Fresh-install test asserting these types are disabled; UI copy review. |
| HK-31 | App Review submissions MUST include Notes for Review that explain the export model, the absence of a vendor endpoint, and a working demo endpoint the reviewer can exercise. | Must | Guideline 2.3.1(a) requires specificity; an app with arbitrary outbound endpoints and a local server cannot be understood without it. [7] | Release checklist item; the notes template lives in the repo. |
| HK-32 | Before Stage 2 closes, we MUST empirically determine and document (a) which types iOS silently caps at hourly, (b) whether background delivery survives Background App Refresh being off, (c) the actual observer-query wake duration, and (d) watchOS lock-state read behaviour. | Must | Apple documents none of these for iOS beyond `stepCount`; the product's honesty depends on knowing them. [4][19] | An on-device measurement harness plus a published findings document. |
| HK-33 | The project MUST decide and record whether to publish under an organisation account rather than an individual, given Guideline 5.1.1(ix). | Should | 5.1.1(ix) directs highly-regulated-field apps to be submitted by a legal entity, not an individual developer. My reading is it should not apply, but the downside is account-level. [7][I] | ADR recorded. |
| HK-34 | Distribution MUST be App Store (iOS/iPadOS/watchOS) plus notarised direct download (macOS). AltStore/sideloading and EU alternative marketplaces MUST NOT be relied on. | Should | Sideloader re-signing is reported to strip the HealthKit entitlement; EU channels require corporate eligibility an individual maintainer lacks and are EU-only. [27][28][34] | Distribution plan review; a test that detects a missing HealthKit entitlement at runtime and shows an honest explanation instead of a broken permission flow. |
| HK-35 | Sleep score, and any other feature visible in Apple's own apps but absent from the SDK, MUST NOT be promised until an SDK type is verified to exist. | Must | No sleep-score identifier exists in the iOS 26.5 SDK headers; the feature is real but appears to be Apple-app-only. [31][40] | The HK-03 enumeration test is the source of truth for what can be claimed. |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Users experience "automatic export" as broken because iOS wakes the app rarely, the device is locked, or they force-quit — and blame the app. | **High** | **High** — this is the core value proposition | HK-13 (honest copy), HK-14 (per-destination status and reasons), a dedicated "why hasn't my export run?" explainer, HK-32 (measure reality before promising anything), and a prominent manual "export now" affordance. |
| App Review rejection under 5.1.3 / 5.1.2 because the app ships health data to endpoints the reviewer cannot inspect. | Medium | **High** — blocks the only consumer channel | HK-23 (no default destination), HK-24 (telemetry off by default), HK-05 (minimal type requests), HK-25 (TLS), HK-26 (deletion path), HK-27 (real health functionality), HK-31 (explicit review notes + demo endpoint). Plan for at least one rejection round in the release schedule. |
| Rejection specifically for requesting a very large number of HealthKit types. | **Medium-High** | High | HK-05 is the mitigation and is non-negotiable: request-on-enable, never request the full set. Screenshot the permission sheet for review notes. |
| 5.1.3(ii) "no PHI in iCloud" invalidates an iCloud Drive / iCloud sync feature that users expect (the reference product has it). | Medium | Medium | HK-21 (no CloudKit, no app-managed container), HK-22 (explicit PM decision recorded as an ADR). Offer Files/document-picker export as the sanctioned alternative. |
| Delta sync drifts because deletions and edits are mishandled; the user's server silently disagrees with Health. | Medium | **High** — silent data corruption in the user's own archive | HK-15/HK-16, plus a reconciliation/verify mode that can compare counts per type per day against HealthKit and report divergence. |
| Memory-driven termination during a multi-million-sample backfill. | Medium | Medium | HK-17 (chunked, resumable, checkpointed), HK-19 (`BGContinuedProcessingTask` for user-initiated bulk work), synthetic large-store testing on the oldest supported device. |
| Users install via AltStore/Sideloadly, get a build with no HealthKit entitlement, and file bugs against a broken permission flow. | Medium | Low-Medium | HK-34: detect a missing entitlement at launch and show an honest "this build cannot access Apple Health; here's why and here are your options" state rather than routing users to a Settings pane the app can never appear in. |
| The Mac companion cannot deliver what "first-class macOS support" implies, and reviewers/users read it as a broken promise. | **High** if unaddressed | Medium | HK-02 plus explicit repositioning in Stage 1 output: the Mac app is a *viewer/importer/receiver*, and we say so everywhere. |
| A future OS release adds types (as iOS 26.2 added `hypertensionEvent`) and our coverage claim silently becomes false. | High over time | Low-Medium | HK-03: enumeration test fails CI on any new unhandled type, forcing an explicit accept-or-exclude decision each SDK bump. |
| App Store sustainability: a solo OSS maintainer stops paying/maintaining the Developer Program membership and users are stranded. | Medium | High | Recorded as a project risk for the PM. Build-from-source must be genuinely viable (documented, no private entitlements), so the project survives loss of the App Store channel. |
| Apple changes background-delivery behaviour in a point release, degrading automation with no API recourse. | Medium | Medium | Nothing we can do technically. HK-32's measurement harness should be re-run each OS release and the published expectations updated. |

---

## Hard constraints that limit the product

These are not negotiable and should be lifted verbatim into the PRD as scope boundaries.

1. **No HealthKit on macOS.** `isHealthDataAvailable()` is always `false`. The Mac cannot read Apple Health, now or
   in any version we can plan against. [1][2][3]
2. **No reads while the device is locked.** `HKErrorDatabaseInaccessible`. Complete-Protection encryption. [6][31]
3. **No app-scheduled background work on iOS.** The system decides when we run. `.immediate` is a ceiling, not a
   promise, and some types are silently capped at hourly (documented for `stepCount` on iOS; most types on watchOS,
   where the budget is four wakes per hour and requires an active complication). [4][19]
4. **The user can switch automation off** by force-quitting, disabling Background App Refresh, or enabling Low
   Power Mode — and we cannot detect the first of these or override any of them. [4][21][R]
5. **We can never know that a read was denied.** Denied reads return empty, by design. [6]
6. **Health data may not be stored in iCloud.** Guideline 5.1.3(ii). No CloudKit sync of health data. [7]
7. **HealthKit data may never be used for advertising, marketing or use-based data mining, including by third
   parties.** Guidelines 5.1.2(vi) and 5.1.3(i). This constrains our own telemetry, not just monetisation. [7]
8. **Clinical records need an entitlement Apple grants only via App Review judgement.** No pre-approval path. [9][10]
9. **Medications and vision prescriptions are per-object authorised.** We cannot get "all medications" with one
   consent; the user grants each one, and new ones are granted from inside the Health app. [15]
10. **ECG voltages, workout routes and heartbeat series need dedicated per-sample queries** — they are not
    obtainable from ordinary sample queries, so their cost scales with sample count, not with query count. [11]
11. **Background delivery does not work in the Simulator.** Every automation claim must be verified on hardware. [4]
12. **Sideloading cannot substitute for the App Store** — re-signing with a free Apple ID is reported to strip the
    HealthKit entitlement. [34]
13. **EU alternative distribution is gated behind corporate financial-eligibility criteria** an individual OSS
    maintainer almost certainly does not meet, and is EU-only regardless. [27][28]

### Where the premise promises something the platform will not deliver

| Premise says | Reality | Honest version |
|---|---|---|
| "first-class support across iOS / iPadOS / macOS / watchOS" | macOS has no HealthKit data. iPadOS only from 17. | "iPhone, iPad (iPadOS 17+) and Apple Watch read your Health data. The Mac app receives, imports and visualises it — Apple provides no way for a Mac to read Apple Health directly." |
| "export, **automate**, and own" (implying scheduled automation) | iOS offers event-triggered best-effort wakes, capped and lock-blocked. No scheduling API. | "Exports run automatically when new health data arrives and your device is unlocked — typically within minutes to an hour. You can also export on demand at any time." |
| Reference-product parity on **iCloud Drive** as a destination | 5.1.3(ii) forbids storing PHI in iCloud; user-picker saves are ambiguous, not permitted. | Files/document-picker export and user-configured endpoints; iCloud only if the PM accepts the documented review risk. |
| Reference-product parity on **"150+ metrics"** | Beatable (~210 non-clinical types) but the count is a bad metric, and clinical records are entitlement-gated. | "Every non-clinical HealthKit type the current SDK exposes, listed in a machine-generated coverage matrix you can audit." |
| "Observable by design" with OpenTelemetry | Default-on outbound telemetry from a HealthKit app is a 5.1.2(i)/5.1.3(i) review risk *in addition to* the privacy tension the brief already identifies. | Tracing off by default, user-configured collector only, never project-owned, never carrying sample values. |
| A **built-in TCP server** for direct reads (reference product) | Not prohibited, but a background-runnable listener on iOS is not possible outside the foreground/short wake windows; and it is exactly the kind of undocumented capability 2.3.1(a) requires us to explain. | A foreground-only local server, clearly described as such, plus push-to-endpoint for unattended operation. |
| "Statistics charts and Home Screen widgets" (reference product) | Achievable, but widget timeline refreshes are also system-budgeted, and widgets cannot read a locked store either. | Widgets show the last known values, with a visible "as of" timestamp. |

---

## Open questions for the PM

1. **iCloud.** Do we ship any iCloud-adjacent destination at all, accepting the 5.1.3(ii) risk (HK-22)? My
   recommendation is no for v1, with Files/document-picker export as the sanctioned alternative.
2. **macOS repositioning.** Is the Mac app a *viewer/importer/receiver* (my recommendation, forced by the platform),
   or do we cut macOS from v1 entirely and spend the effort on iOS reliability?
3. **Publishing entity.** Individual or organisation Apple Developer Program account, given Guideline 5.1.1(ix)
   (HK-33)? This also determines whether EU alternative distribution is ever theoretically reachable.
4. **Who sustains the App Store channel** — the $99/yr, the review cycle per release, the rejection handling? An
   OSS project that cannot answer this should say up front that build-from-source is the primary channel.
5. **Telemetry posture.** Do you accept "off by default, user-configured collector only, no health values ever"
   (HK-24) as the resolution of the brief's stated privacy/observability tension? If tracing must be on by default
   for the differentiator to mean anything, then the differentiator conflicts with the App Store.
6. **Clinical records.** Confirm Won't-have for v1 (HK-08). If you want them, we need a separate release train and
   an appetite for a review fight.
7. **What "automatic" means in the App Store listing.** I need copy approval for the honest wording in HK-13 before
   Stage 2, because the entire reliability design flows from what we are willing to promise.
8. **Measurement budget.** HK-32 needs real devices (an iPhone, an iPad on iPadOS 17+, an Apple Watch) and roughly
   a week of soak testing to establish the real background-delivery envelope. Is that in scope for Stage 2?
9. **Characteristics default.** Confirm that date of birth, biological sex, blood type, skin type and wheelchair use
   are off by default (HK-30), even though it makes our coverage look less complete out of the box.

---

## Sources

1. `isHealthDataAvailable()` — Apple Developer Documentation. "By default, HealthKit data is available on iOS,
   watchOS, and visionOS… also available to iPads running iPadOS 17 or later… The HealthKit framework is available
   on devices running iPadOS 16 and earlier and macOS 13 and later, but your app can't read or write HealthKit
   data. Calls to `isHealthDataAvailable()` return false."
   <https://developer.apple.com/documentation/healthkit/hkhealthstore/ishealthdataavailable()>
2. "HealthKit for iPadOS?" — Apple Developer Forums. Apple Frameworks Engineer: "HealthKit is available for
   applications to link against it on iPadOS and macOS Catalyst. However, `HKHealthStore.isHealthDataAvailable()`
   will return false on those platforms." Later reply confirms iPadOS 17 functionality.
   <https://developer.apple.com/forums/thread/650299>
3. "HealthKit on macOS" — Apple Developer Forums, Sep 2025. Apple DTS Engineer: "your app can't read or write
   HealthKit data on macOS as of today. `isHealthDataAvailable()` will return you `false`." Thread still active
   March 2026 with no change. <https://developer.apple.com/forums/thread/798780>
4. `enableBackgroundDelivery(for:frequency:withCompletion:)` — Apple Developer Documentation. Entitlement
   requirement since iOS 15/watchOS 8; frequency as maximum; `stepCount` hourly cap on iOS; the ten watchOS
   `.immediate` exceptions; four updates/hour watchOS budget requiring an active complication; three-strike
   completion-handler rule; not supported in Simulator.
   <https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:)>
5. `HKObserverQuery` — Apple Developer Documentation.
   <https://developer.apple.com/documentation/healthkit/hkobserverquery>
6. "Protecting user privacy" (HealthKit) — Apple Developer Documentation. Store encrypted when locked; reads may
   fail in the background; writes cached; denied reads indistinguishable from empty.
   <https://developer.apple.com/documentation/healthkit/protecting-user-privacy>
7. App Store Review Guidelines — Apple. Version consulted: **Last Updated June 8, 2026**. Sections used: 1.6, 2.3.1,
   2.4.5, 2.5.1, 2.5.2, 2.5.4, 5.1.1(i)(iii)(ix), 5.1.2(i)(vi), 5.1.3(i)(ii)(iii)(iv).
   <https://developer.apple.com/app-store/review/guidelines/>
8. "Configuring HealthKit access" — Apple Developer Documentation. Capability, entitlement, purpose strings as an
   App Store requirement, clinical-records configuration.
   <https://developer.apple.com/documentation/xcode/configuring-healthkit-access>
9. "HealthKit Capabilities Entitlement" (`com.apple.developer.healthkit.access`) — Apple Developer Documentation.
   Only documented value is clinical records; "App Review may reject apps that don't use the data appropriately."
   <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit.access>
10. "Accessing health records" — Apple Developer Documentation. FHIR/`HKClinicalRecord`, read-only, separate
    permission sheet, privacy-policy URL on the sheet, App Review gating.
    <https://developer.apple.com/documentation/healthkit/accessing-health-records>
11. `HKElectrocardiogramType` — Apple Developer Documentation. Read-only; cannot request share authorisation.
    <https://developer.apple.com/documentation/healthkit/hkelectrocardiogramtype>
12. "Authorizing access to health data" — Apple Developer Documentation. `isHealthDataAvailable()` precondition,
    Guest User mode behaviour, required clinical types.
    <https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data>
13. `HKAnchoredObjectQuery` — Apple Developer Documentation.
    <https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery>
14. `HKDeletedObject` — Apple Developer Documentation.
    <https://developer.apple.com/documentation/healthkit/hkdeletedobject>
15. "Meet the HealthKit Medications API" — WWDC25 session 321. `HKUserAnnotatedMedication`,
    `HKMedicationDoseEvent`, per-object authorisation, Health-app-side authorisation of newly added medications, and
    the explicit warning that dose events are retro-logged, deleted and re-persisted on edit.
    <https://developer.apple.com/videos/play/wwdc2025/321/>
16. "Finish tasks in the background" — WWDC25 session 227. `BGContinuedProcessingTask`: user-initiated only, system
    progress UI, cancellable, priority boost on return; explicitly not for silent sync.
    <https://developer.apple.com/videos/play/wwdc2025/227/>
17. "Choosing background strategies for your app" — Apple Developer Documentation. ~30 s for `BGAppRefreshTask` and
    background push; background `URLSession` for transfers that outlive the app.
    <https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app>
18. `BGProcessingTask` / `BGAppRefreshTask` — Apple Developer Documentation.
    <https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask>
19. "Clarification on HealthKit Observer Query / background delivery" — Apple Developer Forums. Apple DTS: "the
    delivery frequency is not guaranteed… may not achieve that due to the app's background execution time budget and
    other undocumented factors, and there is no API to change the behavior."
    <https://developer.apple.com/forums/thread/823699>
20. "Abnormal Background Delivery Frequency" — Apple Developer Forums. Device-to-device variance (8–16 min vs
    hourly) on identical builds; DTS points to complications and recommends 80%+ battery for testing.
    <https://developer.apple.com/forums/thread/814914>
21. "HKObserverQuery BackgroundDelivery not executed" — Apple Developer Forums, Apr 2026. DTS's two diagnostics:
    completion handler on all paths, and "is the app force quitted when testing?"
    <https://developer.apple.com/forums/thread/823318>
22. `CMFallDetectionManager` — Apple Developer Documentation (entitlement requires an approval request) and the
    request form. <https://developer.apple.com/documentation/coremotion/cmfalldetectionmanager> ·
    <https://developer.apple.com/contact/request/fall-detection-api>
23. `NSHealthRequiredReadAuthorizationTypeIdentifiers` — Apple Developer Documentation. Three-or-more requirement;
    `HKErrorRequiredAuthorizationDenied` without disclosure of which type.
    <https://developer.apple.com/documentation/bundleresources/information-property-list/nshealthrequiredreadauthorizationtypeidentifiers>
24. "Setting up HealthKit" — Apple Developer Documentation. Info.plist keys; `healthkit` required-device-capability
    guidance; note that it is unused by watchOS apps.
    <https://developer.apple.com/documentation/healthkit/setting-up-healthkit>
25. "TestFlight overview" — App Store Connect Help. 90-day build life; ≤100 internal; ≤10,000 external; first build
    per version reviewed.
    <https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/>
26. "Invite external testers" — App Store Connect Help. 10,000 external cap; six Beta App Review submissions per 24 h.
    <https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers>
27. "Changes for apps in the European Union" — Apple Developer Support. Alternative marketplaces and Web
    Distribution require Apple authorisation; Notarization required for all alternatively distributed apps.
    <https://developer.apple.com/support/dma-and-apps-in-the-eu>
28. "Apple announces changes for apps in the European Union" — Apple Newsroom, August 2026. Expanded eligibility
    criteria (D&B financial-stability score, publicly traded, venture funding, completed financial audit,
    government/education/nonprofit) effective 1 October 2026; 5% Core Technology Commission.
    <https://www.apple.com/newsroom/2026/08/apple-announces-changes-for-apps-in-the-european-union/>
29. "Notarizing macOS software before distribution" — Apple Developer Documentation.
    <https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution>
30. Kieran Healy, "Burn Notice", February 2025. First-hand account of an Apple Health export: ~8 million `Record`
    rows since 2018; 30–90 s sample cadence during activity; `export.xml`, `*_cda.xml`, `workout-routes/` structure.
    <https://kieranhealy.org/blog/archives/2025/02/16/burn-notice/>
    Corroborating reports of multi-GB exports and ~790k heart-rate records:
    <https://rud.is/b/2021/02/14/extracting-heart-rate-data-from-apple-health-xml-export-files-using-r-a-k-a-the-least-romantic-valentines-day-r-post/>
31. **Local SDK inspection (primary source).** `iPhoneOS26.5.sdk` in Xcode 26.6 —
    `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/HealthKit.framework/Headers/`.
    `HKTypeIdentifiers.h` (120 quantity / 70 category / 6 characteristic / 2 correlation / 9 clinical / 1 document /
    2 scored-assessment identifiers; `hypertensionEvent` at `ios(26.2)`; medication identifiers at `ios(26.0)`),
    `HKObjectType.h` (factory methods and `requiresPerObjectAuthorization`), `HKDefines.h`
    (`HKErrorDatabaseInaccessible` = "Protected health data is inaccessible because the device is locked";
    `HKErrorNotPermissibleForGuestUserMode`; `HKUpdateFrequency` including `weekly`), `HKStateOfMind.h`
    (7 valence classifications, 38 labels), `HKObserverQuery.h`, `HKAnchoredObjectQuery.h`, `HKHealthStore.h`
    (`requestPerObjectReadAuthorizationForType:predicate:completion:`).
32. Health Auto Export (HealthyApps) — the benchmark product's advertised surface, including iCloud Drive export and
    the "150+ metrics" claim. <https://www.healthyapps.dev/apps/health-auto-export/>
33. `HKUpdateFrequency` — Apple Developer Documentation.
    <https://developer.apple.com/documentation/healthkit/hkupdatefrequency>
34. AltStore PR #1762, "Preserve HealthKit capability when re-signing apps" (opened July 2026, closed as draft):
    "Apps containing `com.apple.developer.healthkit` lose HealthKit access when AltStore or AltServer re-signs them
    because AltSign does not register the matching App ID feature."
    <https://github.com/altstoreio/AltStore/pull/1762>
35. Apple iOS Security white paper (health database in Data Protection class Complete Protection; a separate
    operational database at Protected Until First User Authentication holding access tables and the scheduling
    information used to launch apps when new data is available; temporary journal files at Protected Unless Open).
    **Note: the retrievable copy is the June 2015 edition** — cited for mechanism, corroborated by [6] and by
    `HKErrorDatabaseInaccessible` in [31]. Current equivalent: Apple Platform Security guide.
    <https://www.apple.com/hk/en/privacy/docs/iOS_Security_Guide.pdf> · <https://support.apple.com/guide/security/welcome/web>
36. `HKWorkoutRoute` / `HKWorkoutRouteQuery` — Apple Developer Documentation.
    <https://developer.apple.com/documentation/healthkit/hkworkoutroute>
37. `HKStateOfMind` — Apple Developer Documentation.
    <https://developer.apple.com/documentation/healthkit/hkstateofmind>
38. `requestPerObjectReadAuthorization(for:predicate:completion:)` — Apple Developer Documentation.
    <https://developer.apple.com/documentation/healthkit/hkhealthstore/requestperobjectreadauthorization(for:predicate:completion:)>
39. `HKError.Code.errorRequiredAuthorizationDenied` and the surrounding error list — Apple Developer Documentation
    (includes "The HealthKit data is unavailable because it's protected and the device is locked").
    <https://developer.apple.com/documentation/healthkit/hkerror/code/errorrequiredauthorizationdenied>
40. "New versions of Apple's software platforms are available today" — Apple Newsroom, September 2025. watchOS 26
    sleep score; FDA-cleared hypertension notifications.
    <https://www.apple.com/newsroom/2025/09/new-versions-of-apples-software-platforms-are-available-today/>
