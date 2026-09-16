# Stage 3/4 scope audit

Audit date: 2026-09-14.

This file separates repository-complete engineering work from evidence that cannot be produced honestly without hardware, elapsed time, external accounts, another maintainer, publication, or legal review. “Repository complete” does not mean release-ready.

## Repository-complete controls

- Automatic Data-tab display units follow HealthKit preferred units and refresh on `HKUserPreferencesDidChange`. Export units stay canonical on the wire (UX-44). Region policy remains the fallback when HealthKit does not answer.
- Coverage is re-probed on foreground and before export. A selected type that previously returned data and later returns nothing raises a Status attention row and a Data-tab note (UX-06). Limited-window dates still wait on the HealthKit selector. Device revocation remains a later gate.
- Local archive delivery uses a folder selected through the system Files picker. The scoped bookmark survives relaunch and background/Shortcut exports, refreshes when stale, and must pass the write/read canary again after the folder changes.
- HealthKit characteristics are in the selectable catalogue, off in Core Daily and bulk-select, flagged as re-identifying, and read on demand outside the anchored delta pipeline (HK-30).
- Blood-pressure pairing is emitted as `sample.correlation` beside systolic and diastolic quantity pages. The correlation type stays off the selectable catalogue so it is not a second anchored cursor (ADR-6).
- The Mac companion keeps a last-received clock, shows a quiet watch after three days of silence, and posts a local notification (Q12). Device-to-device radio evidence remains a later gate.
- The iPhone exporter uses four root tabs in fixed order: Status, Data, Destinations, History. Destinations stays second from the right (R-41). Settings opens from the Status toolbar and shows the data-flow explainer, Destinations link, optional privacy gate, and wipe. An iPad exporter shows a permanent Status notice about incomplete Health coverage.
- The status widget maps WidgetKit `fullColor` / `accented` / `vibrant` chrome onto glyph-and-label identity and uses monochrome symbols when hue is stripped (UX-41). When the device is locked it redacts to a lock glyph (SEC-28). The one-shot historical archive may post a Live Activity that dismisses after twenty minutes (UX-25). Greyscale screenshot measurement remains a later gate.
- Destination tests, pinning, connect-time address-class checks, typed public-address confirmation, and explicit MQTT QoS/LWT exclusions are enforced on real transport paths (R-25, R-31, R-32, SEC-09–SEC-15).
- HTTPS export payloads upload from a file handle. On iOS they use a background URLSession so the transfer can outlive suspension; later-wake retries are discretionary (HK-18, ADR-R5). Device terminate-and-relaunch evidence remains a later gate.
- The Home Assistant preset is a dedicated HTTPS webhook destination. It sends the complete native NDJSON feed to `/api/webhook/<id>`, keeps the webhook ID in Keychain and out of portable configuration files, and explicitly does not claim that Home Assistant imports or backdates sensor history from the feed.
- The optional foreground privacy gate fails closed without entering background export or delivery paths; stored credentials have no reveal path (SEC-29, SEC-65).
- Managed state uses the Class C Data Protection floor, payload directories use Class B, SQLite opens with its explicit protection flag, and managed storage is excluded from backup (SEC-30, SEC-32, ADR-0002).
- Destructive wipe covers every app credential service, pairing and signing identities, queued/delivered managed payloads, destination sidecars, logs, snapshots, and preferences. The Mac companion deletes only receipt-ledger-owned archives and documents manual login-keychain cleanup (R-43, SEC-69).
- General pasteboard APIs are prohibited by repository policy across app and source targets (SEC-44).
- Diagnostic, telemetry, and notification redaction use closed schemas and canaries. OTLP is opt-in, HTTP+protobuf only, cardinality-bounded, and has no dedicated background schedule (R-26, R-27, OBS-07, OBS-14, OBS-17–OBS-25).
- T1 generation and pipeline validation cover all ten million records. The full quantity stream is passed through bounded `ExportRun` pages with exact parsed/submitted accounting and a 100 MiB Linux RSS gate. T2 generation covers fifty million deterministic pathological records (R-82, QA-04, QA-19, QA-24).
- Release policy checks cover localization completeness, pseudo/RTL UI suites, privacy manifests and egress inventory, sponsor gating, release issue evidence, flake reporting, focused coverage, and explicit state-transition test evidence (QA-26–QA-33, R-107–R-110).
- Credential-free `.tributary` configuration documents reject unknown/secret fields and can only produce disabled, test-required drafts after exact typed confirmation (R-67, SEC-18).
- A revoked Local Network grant is detected and reported as itself rather than as an unreachable Mac. The companion browser reads its own state, so the mDNS policy error a denial produces is not mistaken for an empty network, and `EPERM` counts as a denial only on a dial that needed the grant. Companion, MQTT, and HTTPS connection failures normalize onto closed `DestinationSendError` values at their transport boundaries, so a denial or unreachable peer is not left as an unclassified transient error. HTTP status, Retry-After, pin, and cancellation failures retain their dedicated types (R-21, TA-01, FIX-A07). Revoking the grant on hardware remains a later gate; the simulator cannot produce the condition.
- Background wakes never migrate the store. A wake opens under a policy that forbids migration and, when the on-disk `user_version` is not this build's, journals `migrationPending` and returns before touching a table; the next foreground launch migrates (ADR-R8). The outcome is in the closed R-21 set and counts as benign for R-22, because an unrecognised journal outcome would otherwise be attributed to us as an execution failure.
- The R-88 soak gate measures the duplicate rate against 0.1% alongside unexplained loss, deriving the rate from `cellsCompared` rather than a self-reported figure, so zero loss bought by duplicating everything cannot sign off clean (TA-06). The validator's own gate is asserted by `policycheck` via a self-test.
- First-release migration evidence is committed at `qa/migrations/v1.json`, binding schema v1 to the current expected version and the CI tests that preserve anchors, journals, destination scopes, process-exit checkpoints, and backfill state (QA-31). The programmatic fixture is test-only in `TestSupport`. A binary store captured from N-1 and an install-N-1-to-N device upgrade cannot exist before v1.0.0; the release checklist explicitly permits the first release and makes the real prior-release artifact mandatory thereafter.
- Each destination persists whether this installation is its designated automatic exporter or is manual-only (AR-15). Manual-only blocks observer, foreground catch-up, app-refresh, processing, and launch triggers while retaining explicit app, Shortcut, and widget-control exports. The same role is durable in `status.json`, so later outcomes cannot make the widget look automatic again; the UI tells people to keep exactly one other installation automatic for a shared destination.
- The scheduled accessibility matrix covers every UI test twice on both iPhone and iPad. It is split into six named shards per family so the measured local suite has room inside the hosted 60-minute job budget; release validation requires all twelve checks, and automation proves the shards contain every test exactly once. Hosted completion remains pending until the revised workflow is dispatched.
- Release validation names all six ordinary iPhone/iPad UI shards and the T1 corpus, T2 pathology, and T2 `ExportRun` checks explicitly; one green matrix leg cannot satisfy a family. QA-22 canary evidence is collected as a retained JSON report and fails closed when stale, or when a red older than 24 hours lacks its generated open tracking issue.
- One Health read serves every destination owed it (AR-02). A page or a repaired day is read once, committed as one canonical batch with a mint-once UUIDv7 identity (R-03) and a monotonic per-exporter sequence (AR-14), and carries one durable obligation per destination. Each destination's payload is projected against its own export window, so a narrower destination receives fewer records from the same batch rather than a second read. The batch and its payload are retained until every destination settles and are unlinked only then. Delivery is audited per `(batch_id, destination_id)` at schema v20, and coverage counts each batch once rather than once per destination.
- Automatic orchestration plans every enabled destination, not the archive folder. Observers, app-refresh, processing, launch, foreground, Shortcut, and Control Centre triggers all fan out, subject to each destination's designated/manual-only role (AR-15). Background wakes queue the Mac companion's obligation without attempting transport and deliver it in the foreground. Whatever any destination is still owed from an earlier read is drained before a new read, bounded lower on background wakes than in the foreground. Enabling, disabling, un-pairing, or changing the role of any destination re-decides the Health observers, so a single non-archive destination is a sufficient wake source. An enabled destination that cannot be reconstructed records its own failure instead of inheriting the outcome of the destinations that ran.
- Reconcile, gap re-export, and historical backfill fan out from the same single read (R-08, R-11). Two destinations are repaired from one observation of a day rather than from separate reads, a backfill job spans the union of its destinations' windows and keeps its destination set across resume, and a destination whose breaker is open keeps its obligation instead of cancelling the repair the others were owed. History shows one parent run row with a child row per destination; child rows are excluded from OTLP so run counts are not inflated.

## Pending automated run

Tier-1 `ExportRun` over all ten million records passes the 100 MiB RSS ceiling
with margin. Measured peak is 51.5 MiB (`outcome=success`, `pages=960`,
`page_size=10000`, `submitted_records=9000000`, all five formats), read from
Linux `VmHWM` in a `swift:6.3.3` container.

GitHub-hosted Linux independently confirms the fix at 66.3 MiB in
[`nightly-volume` run 34999124577](https://github.com/colinedwardwood/open-health-export/actions/runs/34999124577):
`outcome=success`, ten million declared records, nine million submitted,
960 pages of up to 10,000 records, and all five formats under the 100 MiB
ceiling. This is post-fix remote evidence; the failed 145 MiB runs below are
retained as the before measurement.

Getting there took two fixes. A full page was held three times at once — as the
encoded line strings, as the concatenated body, and as the assembled payload —
and then rebuilt a fourth time by the sidecar writers, which read the page back
off disk into records, CSV rows and a `CanonicalJSON` tree. Sidecars alone were
about 50 MiB of a 141 MiB peak. Both paths now stream, and the streaming writers
are pinned byte-identical to the in-memory encoders they replaced.

The measurement is page-size bound, not corpus bound: ingest stays near 36 MiB
from 1.4 million records to 10 million, so a smaller corpus with full 10k pages
reproduces the same peak and is the cheap way to re-check this.

T2 tombstone accounting is on `main` (`volumeStructuralKinds` includes `tombstone`;
`exportruncheck --page-size 10000`). `tier-two-pathologies` on
https://github.com/colinedwardwood/open-health-export/actions/runs/34883238541
concluded success (fifty million records, `pipelinecheck lines=50000001`), and
again on
https://github.com/colinedwardwood/open-health-export/actions/runs/34973680714.
The T2 ExportRun leg is now measured rather than expected. A `swift:6.3.3`
container ran `exportruncheck` over the full fifty-million-record corpus in
2h43m and concluded `outcome=success` at **61.1 MiB** peak `VmHWM` against the
100 MiB ceiling: `declared_records=50000000`, `submitted_records=46894942`,
`structural_records=3105058`, 4,700 pages of 10,000, `samples_read` and
`samples_acked` equal at 57,029,122, and all five formats. Ingest held 27.2 MiB
flat from one million lines to fifty million, so the peak is the page path, as
T1 predicted. The remote `tier-two-exportrun` leg of
[`nightly-volume` run 34999124577](https://github.com/colinedwardwood/open-health-export/actions/runs/34999124577)
is still executing and is what the release gate reads by check name; the local
container run is the measurement, not a substitute for that gate.

The two earlier remote dispatches of `tier-one-corpus` predate the streaming
fix and recorded the old failure (`peak resident memory 145044 KiB exceeded
102400 KiB`). They are superseded by the 66.3 MiB green run above.

Weekly mutation (`qa/mutants.json`) and flake-quarantine skip citations are
wired. Linux kills hostless mutants; macOS kills Darwin-hosted mutants.
Home Assistant `currentStable` is `2026.9.2` after the latest-stable contract
passed.

T2 remains CI evidence, not physical-device evidence.

## External-only release gates

- R-70, R-71 and R-73: named-device HealthKit throughput, background-delivery behavior, cold background launch, and the five-week wake study.
- R-87 / QA-34: signed real-device pass over at least two years and three sources.
- R-88 / QA-35: twenty-one continuous days of soak plus final reconciliation.
- R-33 / SEC-30: real encrypted Finder/iCloud backup and restore inspection.
- R-77–R-79, QA-23–QA-25, OBS-20 and OBS-32: on-device energy, memory, launch, and overhead measurements.
- Manual VoiceOver, locked-device notification/widget, app-switcher snapshot, Hide-and-Require-Face-ID, and other SPIKE-COERCE observations.
- App Store Connect/TestFlight declarations, DSA trader status, review notes, beta cadence, phased release, and notarized distribution.
- Independent clean release build and continuity review. D-10 explicitly rejects
  maintainer recruitment; R-105a/R-105b are not pursued.
- Legal opinions, HIPAA/CRA role determinations, and trademark/name clearance.
- HACS default-list acceptance, Grafana community publication, and real community-device/store-characterisation rows.
- Live advisory-host logging/retention verification and a physical-device release-rehearsal advisory.

Synthetic fixtures, simulator results, templates, and source review must never be substituted for those gates.

## Explicitly deferred Should work

- Signed QR configuration import awaits decisions on signing authority, trust bootstrap, rotation, revocation, and ownership. The credential-free file contract remains available.
- iCloud Keychain synchronization remains absent; credentials stay non-synchronizing and device-only.
- Full OpenTelemetry child-span instrumentation, watchOS network telemetry, and community catalogue publication remain deferred. None weakens the default-zero telemetry or health-export correctness contracts.
- HACS publication is post-v1 work; no listing is claimed.
