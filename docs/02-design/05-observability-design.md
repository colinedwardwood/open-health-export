# Observability Design — Stage 2

**Author:** Observability Engineer
**Stage:** 2 of 4 — System Design
**Status:** Draft for PM synthesis and adversarial review
**Date:** 2026-09-03
**Owns:** R-20…R-27, R-50…R-55
**Inputs:** PRD v1.0 (APPROVED); `contributions/05-observability-engineer.md` (33 `OBS-`);
`contributions/04-security-engineer.md` (vetoes V-1…V-9, SEC-30/32/33/36/37/38/42/43);
`contributions/06-ux-designer.md` (twelve-state status model, UX-22/33/34/35/36/37);
`contributions/03-principal-architect.md` (AR-03/04/12/13/14, NFR-13/14/15);
`02-design/01-system-architecture.md` (ADR-0005 storage, §9.2 outcomes, §9.3 escalation);
`02-design/08-reliability-design.md` (acknowledgement boundaries, outcome severity, freshness
classes)

> Design, not implementation. Schemas, state machines, taxonomies and decision procedures.
> No Swift. Where I need something from another Stage 2 owner, it is called out inline and
> collected in *Open questions*.

> **Reconciliation note.** The architecture and reliability designs landed in parallel with this
> one and overlap it in four places. I have adopted their positions wherever they are better
> argued than mine — the per-sink acknowledgement boundaries, the outcome severity ordering, the
> `L_obs`/`L_del` decomposition and the four freshness classes are theirs and are cited as such.
> Three places do **not** reconcile cleanly and are raised for the PM rather than papered over:
> the Data Protection class of the journal database (Q10), the definition of the escalation
> threshold, which currently has three different forms across three Stage 2 documents (Q11), and
> whether `partial(deferred_discretionary)` is a healthy state (Q12).

---

## Executive summary

The PRD adopted the Stage 1 finding that shapes everything below: on iOS `OSLogStore` can only
be opened with `.currentProcessIdentifier` scope, so the app cannot read logs written by a
previous run of itself. A background wake that failed three days ago is unreachable through OS
logging. **The durable journal is therefore the source of truth, and every other observability
surface in this product — the history UI, the escalation chain, the widget, the diagnostic
bundle, the OTLP projection, the external monitoring signal — is a read of it.**

Five design decisions carry the weight.

**One store, one transaction.** The journal is not a second database. It is a set of tables in
the architect's single SQLite store (ADR-0005), and a run's terminal record commits in the same
`BEGIN IMMEDIATE` transaction as the anchor advance and the outbound-batch write that R-04
already requires. If the journal could disagree with the watermark, R-21's outcome taxonomy would
be computed from something other than what actually happened. That choice grants five of the six
properties I need; the two gaps — the database's Data Protection class, and cross-process writers
— are stated in §The export journal and raised as Q10 and Gap B.

**Runs are sealed per sink, not written.** A run row is inserted *before* any HealthKit read
with a null outcome, fans out to one `run_sink` row per destination, and is advanced phase by
phase. A run whose process died is sealed on the next launch by an ordered ladder that reads how
far **each sink** durably got, and the run outcome is then the most severe sink outcome. This is
what makes R-20's "survives a kill at any point" a property of the schema rather than a hope
about ordering, and it is where the awkward case — a run killed by the OS mid-flight — gets its
answer: `unknown_ack`, never `failed`, because we genuinely do not know whether the bytes
arrived. Sealing per sink matters because a run that wrote the local file and died mid-POST is
two different facts, and one verdict would destroy the more useful one.

**Telemetry does no work during a background wake.** OTLP is a *deferred projection*: the run
writes journal rows it would have written anyway, and a separate projector reads unexported
runs later, on foreground or on Wi-Fi while charging, and emits spans. No span objects are
constructed on the hot path, no batch processor, no persistence decorator, no OTel type touched
during launch. R-79's ≤2% wake-budget ceiling is met by construction rather than by
measurement, and "telemetry survives process death" is free because the journal already does.

**Two of the three escalation rungs must work with our code never running.** The local
notification is pre-scheduled at `lastSuccess + overdue` and re-armed on every success, so
silence fires it. The widget's timeline is a *pre-computed escalation schedule* — future
entries at the known healthy→stale→overdue transition times — so the widget degrades on its own
with no execution and no timeline reload. When notification permission is denied the badge goes
with it (badge is part of the same authorisation), which is precisely why the PRD promoted the
widget to Must, and it is the only passive rung that survives denial.

**Redaction is structural before it is enforced.** The journal physically cannot contain a
destination hostname, an MQTT topic or a user-authored label, because it stores only an opaque
`destination_id` and joins the label at render time for the UI and never for an artefact that
leaves the device. On top of that, the bundle and OTLP serialisers iterate a declared allowlist
manifest rather than the record, so a new journal column is invisible to both until someone
adds it to the manifest with an argued justification. The CI canary tests the encoded forms, and
a canary-of-the-canary job asserts the canary still fails when a leak is deliberately
introduced — which is the answer to RK-5, the erosion risk the security engineer says is the
default outcome.

Four things I am asking the PM to arbitrate rather than deciding myself: a `cancel_source`
discriminator for user-cancelled runs (R-21's enum is closed and I will not add to it); a
user-armed, off-by-default toggle that includes HealthKit type identifiers in the diagnostic
bundle, a documented exception to the security engineer's refusal; the journal database's Data
Protection class, where I disagree with ADR-0005 on a point that should be settled by an
hour's testing on a locked device rather than by argument; and the escalation threshold, which
three Stage 2 documents currently define three different ways. All four are in *Open questions*.

---

## The export journal

### Position in the architecture

The journal is the record of *what the exporter did*. It is distinct from three neighbouring
stores, and the distinction is load-bearing:

| Store | Owner | Contains | Retention |
|---|---|---|---|
| Outbound queue + per-type anchors + high-water marks | Architect (R-04, R-08, R-09) | Health payloads (A4) | Deleted on delivery; 256 MB cap |
| **Export journal** | **This document (R-20)** | Runs, phases, events, counts, outcomes, wakes, attribution. **No health values, no hostnames, no labels** | Tiered; §Retention |
| Egress ledger | Security engineer (R-30, R-41) | One immutable row per transmission | **Never pruned** |
| Configuration | Architect / UX | Destinations, labels, credentials-by-handle, selected types | Life of install |

The journal and the ledger are different artefacts with different jobs. The journal answers
"why did it fail"; the ledger answers "what left this device, and can it be hidden from me"
(it cannot — R-41). They must never disagree, so **the ledger row for a transmission is written
in the same transaction as the journal's `transmit.completed` phase record**, and the journal
run row carries the ledger row's identifier. I am proposing this coupling to the security
engineer rather than asserting it; see *Open questions*.

### What the architect's persistence choice gives me, and the two gaps

ADR-0005 settled this while I was drafting: **one SQLite database behind a `StateStore` port,
via a first-party thin wrapper over system `libsqlite3`, WAL mode, `synchronous=FULL`, a single
`BEGIN IMMEDIATE … COMMIT` transaction idiom, payload blobs as separate files, and a `RunJournal`
module at L3 that owns the journal and the ledger with "redaction applied at write, not at
read".** That is the right choice for me and it grants five of the six properties I need:

1. **Multi-statement ACID transactions with boundaries the engine controls** — granted, and the
   architect's step-7 Commit already puts the batch row, the fan-out rows, the cursor advance,
   the day-census update and the journal event in one transaction. My terminal-transaction
   requirement is that composition plus the ledger row and the `destination_state` rewrite.
2. **Durability against process termination** — granted, and stronger than I asked for.
   `synchronous=FULL` means every commit fsyncs, so the design survives power loss as well as
   process death. I had proposed `NORMAL` with `FULL` only on the terminal commit; **I withdraw
   that** — the architect isolated SQLite on a dedicated thread with a custom executor precisely
   so that fsync does not block the cooperative pool, which removes the cost that motivated my
   weaker proposal. One durability rule everywhere is easier to reason about and easier to test.
3. **A read-only connection that tolerates corruption** — available; §Query patterns Q9.
4. **Data Protection control at the open call** — available (`sqlite3_open_v2` flags applied to
   the database, `-wal` and `-shm`), which is what makes gap A below a decidable question rather
   than a configuration mystery.
5. **A post-commit hook** — available in a hand-written wrapper; I need it so the widget
   snapshot, the notification reschedule and the timeline reload fire exactly once per committed
   state change and cannot diverge from the database.

**Gap A — the protection class may be wrong for a cold open while locked.** The architect
selected `SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN` for the database, reasoning that it is
"what makes C-02 and SEC-32 hold for a background wake that must record a delivery ack while the
device is locked". `CompleteUnlessOpen` permits *creating* a file and continuing to write a file
that was **already open** when the device locked. A background wake several hours after lock
must open the database **cold**, and I do not believe a cold open of an existing
`CompleteUnlessOpen` file succeeds on a locked device. If that is right, the journal is
unwritable during exactly the wakes we most need to record — including every
`healthkit_locked` failure, which is the most frequent failure this product has.

My proposal: **split the classes.** Payload blobs, which are health data, stay at
`CompleteUnlessOpen` (or stronger) as SEC-32 requires. The state and journal database moves to
`CompleteUntilFirstUserAuthentication`, matching the credential class SEC-33 chose for the same
operational reason, and justified by the database containing no health values. This is Q10, it
belongs to the architect and the security engineer jointly, and **it should be settled by a
one-hour empirical test on a locked device rather than by reading Apple's prose**, because the
two readings differ and the failure mode of guessing wrong is silent.

**Gap B — two writer processes.** If App Intents (R-68) or the Shortcuts action run
out-of-process, the app and an extension both write. The architect's model is one `actor` with a
dedicated serial executor, which is a single-*process* discipline. Cross-process writers need a
busy timeout and an advisory lock discipline on top. Not hard, but it must be decided rather than
discovered, and the cheapest resolution is to require that intents perform their work in the app
process.

### Schema

Nine tables. Every enumerated column draws from a compile-time-closed set declared once in the
allowlist manifest (§Redaction) and shared by the journal, the metrics and the OTLP projection,
so the three cannot drift.

#### `run` — one row per export run attempt

**A run fans out to one or more destinations.** The architecture design's step-7 Commit writes
"per-destination fan-out rows", and the reliability design computes a per-sink terminal state
before deriving the run outcome. I have restructured to match: run-level facts live here,
per-destination facts live in `run_sink`, and the run outcome is derived from the sinks rather
than stored independently of them.

| Column | Type | Notes |
|---|---|---|
| `run_id` | ULID | Monotonic by construction; sorts by time without an index on time |
| `run_seq` | int64 | Per-install monotonic sequence (AR-14); survives clock changes |
| `trigger` | enum(8) | `manual`, `observer_query`, `bg_app_refresh`, `bg_processing`, `bg_continued`, `shortcut`, `app_foreground`, `widget_control` |
| `wake_id` | ulid | FK → `wake`. Null only for in-process foreground runs chained to an existing wake |
| `mode` | enum(5) | `delta`, `full`, `backfill`, `reconcile`, `destination_test` |
| `started_at` | int64 | Wall clock, ms since epoch |
| `started_uptime` | int64 | Monotonic (system uptime) at start |
| `ended_at`, `ended_uptime` | int64 | Null while in flight |
| `duration_ms` | int64 | **Computed from the uptime pair, never from wall clock.** Immune to time changes and DST |
| `tz_offset_min` | int16 | Offset at run start, for honest local-time rendering (R-10) |
| `clock_anomaly` | enum(3) | `none`, `jumped_forward`, `jumped_backward` — set when wall and monotonic deltas disagree by >5 min |
| `outcome` | enum(7)? | **Null means in flight.** Derived from the sinks by the severity rule in §Outcome taxonomy |
| `cancel_source` | enum(3)? | `system_budget`, `user`, `os_termination`. See *Open questions* Q1 |
| `seal_reason` | enum(4) | `normal`, `swept_on_relaunch`, `swept_on_wake`, `forced_by_prune` |
| `attribution` | enum(2)? | `scheduling`, `execution` — R-22's binary split |
| `attribution_detail` | enum(9)? | Sub-class; §Failure attribution |
| `attribution_confidence` | enum(3)? | `evidenced`, `inferred`, `unknown` |
| `samples_read` | int32 | Post-filter. **Read once per run, fanned out to sinks** |
| `types_attempted` | int16 | Count only |
| `budget_ms_granted`, `budget_ms_used` | int32? | For `abandoned_no_budget`; null when not budgeted |
| `device_locked_observed` | bool | Protected data unavailable at any point in the run |
| `low_power_mode`, `charging` | bool | At run start |
| `network_class` | enum(4) | `wifi`, `cellular`, `wired`, `unavailable` |
| `trace_id`, `root_span_id` | bytes(16), bytes(8) | Generated at run start regardless of OTLP state; §The OTLP projection |
| `app_version`, `os_version` | enum-interned | Interned into a small dictionary table; needed to diagnose across updates |
| `projected_at` | int64? | OTLP export watermark, per run |
| `schema_version` | int16 | Journal schema version at write time |

#### `run_sink` — one row per (run, destination)

| Column | Type | Notes |
|---|---|---|
| `run_id`, `destination_id` | ULID, uuid | Composite key. `destination_id` is opaque and random at destination creation. **Never derived from the URL** — a hash of a guessable hostname is not anonymisation (SEC-37) |
| `sink_outcome` | enum(7)? | Same vocabulary as the run; null while in flight |
| `partial_cause` | enum(6)? | Reliability design's mandatory cause code: `deferred_discretionary`, `awaiting_unmetered`, `awaiting_wifi`, `budget_exhausted`, `breaker_open`, `types_purged` |
| `error_class` | enum(~35)? | Closed catalogue; §Signal taxonomy. **No free-text error column exists in this schema** |
| `error_phase` | enum(9)? | Which phase raised it |
| `samples_sent` | int32 | Handed to a transport write that completed |
| `samples_acked` | int32 | Positive delivery evidence held, **from this run's own batches** |
| `samples_acked_total` | int32 | Including confirmations of older queued batches |
| `samples_rejected` | int32 | Destination said no |
| `ack_units_total`, `ack_units_confirmed` | int16 | §Outcome taxonomy defines the acknowledgement unit |
| `ack_evidence` | enum(8) | `http_2xx_receipt`, `http_2xx`, `mqtt_puback`, `mqtt_pubcomp`, `mqtt_qos0_write`, `file_fsync_rename`, `companion_receipt`, `none` |
| `bytes_serialised`, `bytes_transmitted` | int64 | |
| `attempt_count` | int16 | Retries within this run |
| `transport_security` | enum(5) | `tls13`, `tls12`, `plaintext_optin`, `local_file`, `n_a` |
| `traceparent_emitted` | bool | R-54 |
| `ledger_id` | ulid? | FK → egress ledger, when bytes left the device |
| `format` | enum(4) | `ndjson`, `json`, `csv`, `hae_json` |

#### `run_phase` — per-phase timings

One row per phase entered. `run_id`, `destination_id?`, `phase` ∈ {`discover`, `query`,
`transform`, `serialise`, `transmit`, `acknowledge`, `commit`, `retry`, `seal`},
`started_uptime`, `ended_uptime`, `duration_ms`, `outcome` ∈ {`ok`, `error`, `interrupted`},
`error_class?`. `destination_id` is null for the run-level phases (`discover`, `query`) and set
for the per-sink phases (`serialise` onward), which is what lets the sealing ladder ask "how far
did *this sink* get" rather than "how far did the run get". The phase set is the
same closed set as the span names in §Signal taxonomy, so the OTLP projection is a rename, not
a mapping.

Phase rows are the durability ratchet: **a phase row's commit is the evidence used by the
sealing ladder.** `transmit` in particular is committed twice — once at `started`, once at
`ended` — because the interval between them is the only window in which we cannot know whether
data arrived.

#### `run_type_stat` — per-type counts within a run

`run_id`, `type_family` (interned; ~40 curated families plus a `passthrough` bucket),
`type_id` (interned identifier — **journal-local only, never egressed, never bundled by
default**), `read`, `sent`, `acked`, `rejected`, `window_start`, `window_end`. This is the
highest-row-count table and is Tier-A retention only (§Retention). It is what makes `partial`
attributable to a type and what feeds the coverage check that stops `success_nothing_due`
from masking a revoked authorisation.

#### `run_event` — ordered events within a run

`run_id`, `seq`, `at_uptime`, `event` (closed enum of ~35 values, e.g. `anchor_read`,
`anchor_advanced`, `batch_enqueued`, `queue_evicted`, `retry_scheduled`, `circuit_opened`,
`cert_pin_matched`, `cert_pin_changed`, `plaintext_optin_used`, `traceparent_sent`,
`traceparent_auto_disabled`, `observer_completion_called`, `budget_warning`, `clock_anomaly`),
plus up to three typed numeric slots (`n1`, `n2`, `n3`) and one enum slot. **No string slot.**
These become OTel span events on the run span (§The OTLP projection).

#### `wake` — every entry into our code

`wake_id`, `at`, `at_uptime`, `trigger` (same enum as `run.trigger`, plus `launch`),
`process_instance_id`, `app_state` ∈ {`foreground`, `background`, `prewarm`},
`protected_data_available`, `bg_refresh_status` ∈ {`available`, `denied`, `restricted`,
`unknown`}, `low_power_mode`, `disposition` ∈ {`ran_export`, `nothing_due`, `bailed_locked`,
`bailed_no_network`, `bailed_paused`, `bailed_budget`, `bailed_error`, `telemetry_only`},
`runs_started` (int16).

**Wakes that produce no run still get a row.** That is the whole point: "we were woken and
declined" and "we were never woken" are different facts with different remediation, and only
the first leaves evidence at the time it happens.

#### `bg_submission` — what we asked the OS for

`submission_id`, `submitted_at`, `identifier` (closed enum of our task identifiers),
`earliest_begin_at`, `serviced_wake_id?`, `serviced_at?`, `cancelled_at?`. The gap between
`earliest_begin_at` and `serviced_at` is the empirical scheduling-latency distribution, which
is both the failure-attribution denominator (§Failure attribution) and the per-device input to
the freshness target (§Freshness target N).

#### `process_instance` — evidence of our own death

`process_instance_id`, `started_at`, `started_uptime`, `boot_id` (derived from boot time),
`app_version`, `os_version`, `clean_exit` (bool, default false), `last_heartbeat_uptime`.
`clean_exit` is set on `applicationWillTerminate` and on background-task expiry handlers. A row
with `clean_exit = false` and no successor heartbeat is evidence of an unclean end; the *cause*
comes from MetricKit (§Failure attribution).

#### `destination_state` — the materialised current state

One row per destination, rewritten in the same transaction as any terminal run write. This is
the state that drives every user-facing surface, and it exists so that the widget, the
watchdog, the notification scheduler and the Status screen cannot disagree (UX-34).

`destination_id`, `enabled`, `paused`, `cadence_class`, `cadence_seconds` (*C*),
`freshness_class_tightest`, `stale_threshold_s`, `overdue_threshold_s` (both from the single
threshold function of §Freshness target N — pre-spike from *C*, post-spike from `N_p95`),
`last_success_at`, `last_success_run_id`, `last_unconfirmed_send_at`, `last_run_at`,
`last_run_outcome`,
`last_confirmed_ack_at`, `consecutive_actionable_failures`, `nothing_due_streak_runs`,
`nothing_due_streak_since`, `state` (UX's twelve-value enum), `attribution?`,
`attribution_detail?`, `error_class?`, `notification_policy_version`,
`scheduled_notification_fire_at?`, `snapshot_written_at`.

#### `run_daily_rollup` — the long tail

`day` (local date at `tz_offset_min`), `destination_id`, per-outcome counts, `first_success_at`,
`last_success_at`, `max_gap_s`, `runs`, `samples_acked`. Written when Tier-B pruning removes
run rows, so the honest long-range history survives at negligible cost (§Retention).

#### `journal_meta`

`schema_version`, `install_id` (opaque, local-only, never egressed), `created_at`,
`last_prune_at`, `last_sweep_at`, `otlp_watermark_run_seq`, `degraded_flags`.

### Durability across process death

**The write protocol.** Every run follows the same ratchet, and each step is a committed
transaction:

1. `wake` row inserted before any work, in the same transaction as `process_instance` heartbeat.
2. `run` row inserted with `outcome = NULL`, before the first HealthKit query.
3. `run_phase` row per phase boundary. `transmit` commits at start and at end.
4. Terminal transaction — and this is the one that matters — commits **together**, in the
   architect's single `BEGIN IMMEDIATE … COMMIT` idiom: the `run` and `run_sink` outcomes and
   counts, the final `run_phase` rows, the egress `ledger` row, the anchor advance, the
   outbound-queue mutation, the day-census update, and the `destination_state` rewrite. R-04
   already requires the anchor and the batch to be atomic; I am adding the record of it, and the
   materialised state every user-facing surface reads, to the same transaction.
5. Post-commit, outside the transaction: write the widget snapshot file, reconcile the scheduled
   notification, request a widget timeline reload. These are idempotent and derived, so losing
   them costs a refresh, never correctness.

**What this survives.** Under the architect's WAL + `synchronous=FULL` configuration: SIGKILL,
jetsam under memory pressure, `BGTask` expiry, force-quit, app update, device restart, **and**
power loss and kernel panic, because every commit fsyncs. I had proposed `synchronous=NORMAL`
with `FULL` only on the terminal commit, to avoid paying an fsync per phase boundary inside a
30-second wake budget; I withdraw it. The architect gave SQLite a dedicated thread with a custom
serial executor specifically so that a blocking fsync cannot starve the cooperative pool, which
removes the cost that motivated the weaker setting, and one durability rule everywhere is easier
to reason about and far easier to test than a rule with an exception in it.

The residual cost is real and belongs in the wake-budget arithmetic rather than in this section:
roughly a dozen fsyncs per run. That is the reliability design's NFR territory, and it is the one
number I would want measured on REF-B before M3 exits, because a phase-boundary fsync that costs
more than a few milliseconds would push me back toward the exception I just withdrew.

**The sealing ladder.** On every launch and at the start of every background wake, before any
new work, the sweep finds `run` rows with `outcome IS NULL` whose `process_instance_id` is not
the current one. **Each `run_sink` row is sealed independently** by the furthest durably
committed phase *for that sink*, and the run outcome is then derived from the sealed sinks by
the severity rule. Sealing per sink matters: a run that delivered to the local file and died
mid-POST to Home Assistant is `success` for one sink and `unknown_ack` for the other, and
collapsing that to a single verdict would lose the only fact the user needs.

| Furthest committed evidence | Sealed outcome | Rationale |
|---|---|---|
| No `transmit` phase row | `cancelled_by_system`, `cancel_source = os_termination` | Nothing left the device |
| `transmit` started, not ended | **`unknown_ack`**, `ack_evidence = none` | Bytes may or may not have arrived. We do not know, so we do not claim |
| `transmit` ended, `acknowledge` not ended | **`unknown_ack`** | We wrote; we never read the answer |
| `acknowledge` ended | Apply the full decision procedure to the recorded counts | We have the evidence; the crash was after the fact |

All sealed rows carry `seal_reason = swept_on_relaunch` and are rendered in history with an
explicit "interrupted" note. The sweep is bounded (≤ 200 rows per pass, oldest first) so it
cannot itself blow a wake budget, and it is idempotent.

**Data Protection class.** My position is
`NSFileProtectionCompleteUntilFirstUserAuthentication` for the state and journal database,
matching the credential class SEC-33 chose for the same operational reason: background wakes
happen while the device is locked, and **the single most common failure we must record is the
one where HealthKit was locked**. A journal we cannot open while locked cannot record the
locked-device failure, which would leave the app silent about its most frequent problem. It is
a weaker class than the payload blobs', and it is justified only because the database contains
no health values — a property the R-51 allowlist enforces structurally, not by review.

This **conflicts with ADR-0005**, which puts the whole database at
`SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN`. See Gap A above: the disagreement is over
whether a *cold open* of an existing `CompleteUnlessOpen` file succeeds on a device that has been
locked for hours, and it should be settled by a one-hour test on a real locked device rather than
by reading Apple's prose, because the two readings differ and guessing wrong fails silently.
Raised as Q10; ADR-OBS-03 is written as a proposal contingent on that test.

Consequence, stated: **a wake occurring after boot but before the first unlock is unobservable
to us.** We cannot even record that it happened. This biases wake counting downward, which
biases attribution toward "the OS never woke us". The bias is tolerable because HealthKit is
unreadable in that window anyway (C-02), so such a wake could not have produced an export, and
both attributions lead to the same remediation copy ("nothing you can do"). I considered a
`NSFileProtectionNone` beacon file to close the gap and rejected it: a boot-time beacon is
behavioural metadata (A6) and the gain does not justify the class.

**Backup exclusion.** `NSURLIsExcludedFromBackupKey` on the journal directory (OBS-33, SEC-30),
as defence in depth: a redaction defect must not be able to become an iCloud disclosure under
5.1.3(ii). The cost is real and must be surfaced in copy: **export history does not migrate to
a new device.** On first launch with an empty journal and a non-empty configuration, every
destination enters `Never run`, never `Healthy`, and the Status screen states that history was
not carried over. A restored device that silently showed "Healthy" from a stale snapshot would
be exactly the false-success bug we exist to eliminate.

### Retention and pruning

Three tiers, and the guarantee is expressed as "prune only when *both* bounds are exceeded",
because a guarantee of "90 days or 1,000 runs" that prunes at whichever comes first is not a
guarantee of either.

| Tier | Contents | Kept while | Pruned to |
|---|---|---|---|
| A — full detail | `run_phase`, `run_type_stat`, `run_event` | run is within the most recent 200 **and** newer than 30 days | dropped; `run` row retains totals |
| B — run summary | `run` rows, `wake`, `bg_submission` | run is within the most recent 1,000 **or** newer than 90 days | rolled into Tier C |
| C — daily rollup | `run_daily_rollup` | 400 days | dropped |
| — | egress ledger | **never pruned** (R-41) | — |

**Footprint budget.** Tier A ≈ 200 runs × (8 phases + ~40 type stats + ~15 events) ≈ 12,600
rows. Tier B ≈ 1,000 run rows + wakes. Tier C ≈ 400 × destinations. At three destinations this
is ~2.5 MB including indexes, inside the ≤ 5 MB SLO-7 budget with headroom. The ledger has its
own budget and its own honest growth statement: one row per transmission, ~48 bytes packed; at
24 transmissions/day across 3 destinations that is ~1.3 MB/year, ~6.5 MB over five years. It is
never compacted — merging identical consecutive rows in a tamper-evidence record is
tamper-adjacent — so the correct answer is to publish the growth rate, not to hide it. Flagged
to the security engineer.

**When pruning runs.** Foreground only, at most once per 24 hours, in bounded transactions of
≤ 500 deletions per pass with the pass repeated until quiescent or a 200 ms budget is spent.
**Pruning never runs during a background wake** — the wake budget belongs to the user's data.
A hard-cap emergency prune triggers if the journal exceeds 2× budget, drops Tier A first, and
records `ohe.telemetry.dropped{reason="emergency_prune"}` plus a visible history note.

**Interaction with the OTLP projection.** A run pruned before it is projected is lost to the
user's collector. The rule is that the journal outranks OTLP (PRD §6.4): pruning defers for
unprojected runs up to a backlog cap of 5,000 runs or 30 days, after which pruning wins, the
watermark jumps, and the drop is counted and surfaced.

### Query patterns the UI needs

Every read the product performs, with the access path that serves it. If a screen needs a query
not on this list, the journal schema is wrong and I want to hear about it in Stage 3, not
discover a table scan on a five-year-old install.

| # | Consumer | Query | Path |
|---|---|---|---|
| Q1 | History list | Runs newest-first, optionally filtered by destination and outcome, paginated 50 | `run_id` is a ULID → primary key descending; index on `run_sink(destination_id, run_id DESC)` for the filtered case |
| Q2 | Run detail | One run + its sinks, phases, events, type stats | PK + four FK lookups |
| Q3 | Status screen, destination list | Current state for all destinations | Full read of `destination_state` (≤ 8 rows) |
| Q4 | Widget, Control Centre | Current state, no database access | Reads the App Group **snapshot file**, not SQLite; §The escalation chain |
| Q5 | Watchdog | Staleness per destination | `destination_state` |
| Q6 | Failure attribution | Wakes, submissions and runs in `[last_success, now]` | Index on `(at)` for `wake`; `(earliest_begin_at)` for `bg_submission` |
| Q7 | Coverage / data browser cross-check (R-69) | Last acked time per (destination, type) | Materialised `type_state` projection maintained in the terminal transaction, not a scan of `run_type_stat` |
| Q8 | Freshness distribution | p50/p95 of `L_obs` and `L_del`, per freshness class, over the last 30 days | Tier-A scan bounded to 200 runs; recomputed at most hourly and cached in `journal_meta` |
| Q9 | Diagnostic bundle | Last N runs, full detail, tolerant of corruption | Separate read-only connection, `integrity_check` first, row-salvage fallback |
| Q10 | OTLP projector | Runs with `projected_at IS NULL` and `run_seq > watermark` | Partial index on `projected_at IS NULL` |
| Q11 | External monitoring | Last success age for one destination | `destination_state`, single row |
| Q12 | Long-range history chart | Daily outcome counts over 400 days | `run_daily_rollup` |

---

## Outcome taxonomy

R-21 fixes the vocabulary: `success`, `success_nothing_due`, `partial`, `unknown_ack`,
`failed`, `abandoned_no_budget`, `cancelled_by_system`. This section fixes the meaning.

### The acknowledgement unit

Everything below depends on one definition, because "did it arrive" is only answerable at the
granularity the protocol answers it.

> **The acknowledgement unit is the smallest unit of work for which the destination can give
> independent delivery evidence.**

| Destination | Acknowledgement unit | Confirming evidence | Not evidence |
|---|---|---|---|
| Local file | One file, written to temp, fsynced, atomically renamed, re-stat'ed for size | `file_fsync_rename` | A successful `write()` without fsync |
| HTTPS (generic, HA preset, HAE profile) | One HTTP request | 2xx; **2xx with a parsed receipt naming accepted/rejected counts is stronger and is what our wire spec and reference receiver emit** | Connection established; TLS handshake; 2xx from a proxy that discarded the body — which is why R-25's test sends a real payload |
| MQTT QoS 0 | — none exists — | **nothing** | `write()` completing. The broker may accept and drop |
| MQTT QoS 1 | One PUBLISH | PUBACK | — |
| MQTT QoS 2 | One PUBLISH | PUBCOMP | — |
| Mac companion | One job frame | Application-level receipt carrying the batch id and accepted count | A cleanly closed TCP connection |

This table is the same boundary set the reliability design derives independently, and where we
differ I defer to it: its Home Assistant row is the sharper observation, that a 2xx from
`POST /api/states/<entity>` tells us the state was accepted and tells us *nothing* about whether
the recorder or the long-term statistics engine took it. R-89's `state_class` failure is
invisible in the response, so that gap is closed at configuration time by R-25's read-back test,
not at delivery time. **This is the one sink where the acknowledgement is weaker than it looks**,
and the journal must not pretend otherwise: `ack_evidence = http_2xx` for HA, never
`http_2xx_receipt`, so the distinction is visible in the record rather than living only in a
design document.

Two consequences. **The per-type watermark advances per acknowledgement unit, not per run** —
a run that fully acked three types and failed the fourth advances three watermarks. And
**MQTT QoS 1's PUBACK confirms the broker received it, not that anything is subscribed**, so
its user-facing copy says "the broker confirmed receipt" and offers the echo-verify option
described under R-25 rather than claiming delivery to a consumer.

For the local-file destination, our evidence is that the bytes are fsynced at the URL the user
chose. What the file system does afterwards — including a user-chosen iCloud-backed folder —
is the file system's business and the user's choice made in Apple's own UI (PC-3). We ship no
iCloud code and we detect no upload state; the destination's help text says so in one sentence.

### Symbols

Per **sink** (a run has one or more): `R` samples read in the run (post-filter); `S` sent within
a completed transport write; `A` acked **from this run's own batches**; `X` explicitly rejected;
`D` the set of types with candidate work; `U` acknowledgement units attempted, `U_c` confirmed;
`E` the `ack_evidence` class. `A` is scoped to this run's batches rather than to all
confirmations observed during the run, because a run that happens to drain three older queued
batches has not thereby delivered its own work — that scoping is the reliability design's, and
it closes a way in which R-21's invariant could be satisfied dishonestly.

### The per-sink decision procedure

Evaluated exactly once per `run_sink`, at seal, first match wins. It is a total function — every
sink gets an outcome — and rule 11 existing at all is a defect detector, not a fallback.

| # | Condition | Outcome | Notes |
|---|---|---|---|
| 1 | Run was swept (process died) | **the sealing ladder** (§Durability) | Interruption is decided by evidence, not by counts |
| 2 | User cancelled | `cancelled_by_system`, `cancel_source = user` | See Q1 — I will not add an eighth enum value |
| 3 | OS signalled expiry/budget exhaustion, before or during transmit | `abandoned_no_budget` | Distinct from failure: nothing is wrong, we ran out of time |
| 4 | A fatal error occurred and no bytes left the device | `failed` + `error_class` | The clean failure case |
| 5 | `D = ∅` **or** (`R = 0` and every type read completed without error **and** this sink's queue is empty) | `success_nothing_due` | Advances the freshness clock (OBS-11). Increments `nothing_due_streak`. A locked-store read is **not** "nothing due" — it is `failed(healthkit_locked)` |
| 6 | `E ∈ {mqtt_qos0_write, none}` and the transport write completed without error | **`unknown_ack`** | **Regardless of counts.** Non-confirmable transports can never produce `success` |
| 7 | `A = R` and `R > 0` and `X = 0` and `U_c = U` and `E` is confirming | `success` | The only path to success |
| 8 | `0 < A < R`, or `X > 0` with `A > 0`, or `0 < U_c < U`, or `S = R` with acks outstanding | `partial` + **mandatory `partial_cause`** | Cause ∈ `deferred_discretionary`, `awaiting_unmetered`, `awaiting_wifi`, `budget_exhausted`, `breaker_open`, `types_purged` |
| 9 | `A = 0` and the transport reported a definite failure | `failed` + `error_class` | |
| 10 | `A = 0`, no definite failure, `E` confirming but absent | `unknown_ack` | e.g. a response we could not parse |
| 11 | otherwise | `failed`, `error_class = unclassified` | **A defect.** Emits `ohe.telemetry.dropped{reason="unclassified_outcome"}`; a test asserts this rule never fires across the fault-injection matrix |

R-21's hard invariant — *never `success` when `A < R`* — is rules 7 and 8 together, and it is
additionally enforced as a database CHECK constraint on `run_sink`
(`sink_outcome = 'success'` implies `samples_acked = samples_read AND samples_rejected = 0`), so
a future refactor that gets the procedure wrong fails at write time rather than lying to the
user. That constraint is the cheapest insurance in this document against the incumbent's
defining bug.

### From sinks to the run outcome

The run outcome is the **most severe** sink outcome, under the reliability design's ordering,
which I adopt unchanged so that two Stage 2 documents do not define two orderings of the same
enum:

`success_nothing_due` < `success` < `partial` < `unknown_ack` < `abandoned_no_budget`
< `cancelled_by_system` < `failed`

Its two contentious placements are argued there and I agree with both: `failed` above
`cancelled_by_system` because "we ran and could not deliver" is more actionable than "the OS
stopped us", and `unknown_ack` above `partial` because ambiguity about data we may have
delivered is worse than certainty about data we did not.

**The run outcome is a summary, never the thing the user acts on.** Every user-facing surface
that offers a fix reads `run_sink`, because "partial" across four destinations is three different
problems. The run outcome exists for the history list's one-line summary, for the metric
dimension, and for the OTLP root span — all three of which are aggregate views by nature.

### The awkward cases, worked

**MQTT QoS 0.** Rule 6 fires before rule 7 can. There is no configuration, no counts and no
broker behaviour that produces `success` on QoS 0, and MQTT defaults to QoS 1 so that reaching
this state is always an opt-in the user made with the consequence named in the same sentence.

The awkward part is the freshness clock, and the reliability design resolves it better than my
draft did. If `unknown_ack` never sets a last-success timestamp, a QoS-0-only destination has no
last-success clock at all and the R-23 watchdog fires forever — an alarm that is technically
true and practically useless. So: **a QoS 0 destination runs a separate, clearly labelled
"last unconfirmed send" clock**, `destination_state` carries both `last_success_at` and
`last_confirmed_ack_at`, and the escalation copy for that destination says *"we cannot confirm
delivery to this destination — MQTT QoS 0 provides no acknowledgement"* rather than *"exports
have stopped"*. The destination never reaches `Healthy`; it sits at `Sent, unconfirmed`, which is
the truth, and it escalates on the unconfirmed clock rather than not at all. R-27's external
signal exposes both timestamps so the user's own monitoring chooses which it trusts.

**Partially acknowledged batch.** Two sub-cases, both `partial`:
*(a) per-record results.* The destination returns accepted and rejected counts (our wire spec's
receipt, or an HTTP 207-style body). `A` and `X` come from the receipt; rejected records are
re-queued with a `rejection_reason` enum and the affected types' watermarks do not advance.
*(b) multi-request runs.* We split a run into several acknowledgement units and some succeed.
`U_c < U`; watermarks advance only for fully confirmed units. History renders "Exported 380 of
412 samples to Home Assistant — 32 rejected (unsupported unit). We'll retry those." The run is
never `success`, and the retry is visible rather than implicit.

**Run killed by the OS mid-flight.** The sealing ladder. If we had committed `transmit.started`
and nothing after, the outcome is `unknown_ack` — not `failed`, because claiming failure would
be as dishonest as claiming success, and the destination may well hold the data. The watermark
did not advance, so the next run re-sends and upsert-by-UUID (R-02) makes the duplicate
harmless. The history entry says "Interrupted — we don't know whether this arrived", which is
the sentence the incumbent never writes.

**The `success_nothing_due` trap.** A destination whose HealthKit authorisations were all
revoked reads zero samples, errors on nothing, and would report `success_nothing_due` forever
while delivering nothing — a slow-motion false success. Closed by two mechanisms:
`nothing_due_streak_runs` / `nothing_due_streak_since` on `destination_state`, and a **coverage
check**: when the streak exceeds max(7 days, 20 runs) *and* `type_state` shows those types have
produced data historically, the destination moves to `Partial` with copy that states both
possible causes and does not assert denial (R-60: Apple guarantees denial is indistinguishable
from absence, so we say "there is no new data for these types, or access to them is off in
Health — we cannot tell which", and offer the path into Health).

### Mapping to user-facing state and copy

The outcome enum and UX's twelve-state model are different vocabularies; this table is the
contract that makes UX-34 ("no two surfaces disagree") mechanically checkable, because both
sides derive from `destination_state` and this mapping is the only place the translation happens.

| Outcome | Destination state | History row (title) | Counts toward consecutive failures | Escalates |
|---|---|---|---|---|
| `success` | `Healthy` | "Exported 412 samples to *Home Assistant*" | no | no |
| `success_nothing_due` | `Healthy` (or `Partial` on coverage trip) | "Nothing new to export" | no | no |
| `partial(deferred_discretionary \| awaiting_wifi \| awaiting_unmetered)` | `Deferred` | "Waiting for Wi-Fi" / "Queued" | no | via staleness only |
| `partial(budget_exhausted \| breaker_open \| types_purged)` or rejected records | `Partial` | "Exported 380 of 412 — 32 rejected" | no | on repetition |
| `unknown_ack` | `Sent, unconfirmed` | "Sent — delivery not confirmed" | no | via staleness only |
| `failed` (actionable class) | `Failing` or `Blocked` | The error catalogue's ① title | **yes** | yes |
| `failed` (`healthkit_locked`, `no_network`, `low_power`) | `Deferred` | "Waiting — iPhone was locked" | no | via staleness only |
| `abandoned_no_budget` | `Deferred` | "iOS stopped the export early" | no | via staleness only |
| `cancelled_by_system` (`os_termination`) | `Deferred` | "Interrupted" | no | via staleness only |
| `cancelled_by_system` (`user`) | unchanged | "Cancelled" | no | no |

Three rules the table encodes and that I want quoted in review: non-actionable outcomes never
inflate the failure badge, they *always* count toward staleness (so silence still escalates),
and `Deferred` never masquerades as success.

---

## Failure attribution: scheduling vs execution

R-22 requires that "the OS never woke us" be attributed separately from "we ran and failed".
The difficulty is that the app cannot log the absence of a wake at the moment it does not
happen. Attribution is therefore **reconstructed retrospectively from four independent evidence
sources**, and stated with a confidence level rather than asserted.

### The evidence sources

**E1 — the wake ledger (positive evidence of presence).** Every entry into our code writes a
`wake` row before any work, including wakes that bail. "We ran" is directly evidenced. The
absence of rows in an interval is *negative* evidence and is only as good as our ability to
write during that interval — which is why the journal's Data Protection class matters and why
the pre-first-unlock blind spot is stated rather than hidden.

**E2 — the submission ledger (evidence of what we asked for).** Every `BGTaskScheduler`
submission and every `enableBackgroundDelivery` registration is recorded with its requested
earliest date. A submission whose earliest date is long past with no `serviced_wake_id` is
direct evidence that the OS declined. This is the denominator R-22 needs and it is honest,
because it compares against *what we requested*, not against a schedule the platform never
promised (PC-2).

**E3 — MetricKit exit and diagnostic payloads (evidence of why we ended).** `MXAppExitMetric`
reports, on the next launch, the previous day's exit reasons: normal exit, memory resource
limit, background-task assertion timeout, watchdog, illegal instruction, and so on.
`MXCrashDiagnostic` and `MXHangDiagnostic` corroborate. This is the mechanism by which the app
observes the *cause* of its own absence. Two limits, stated: payloads are delivered at most
once per day and are aggregated over 24 hours, so they are a coarse corroborator that can
raise confidence but cannot attribute a single run; and MetricKit was rebuilt for iOS 27 with a
new `MetricManager` API, so this evidence source has a known migration ahead of it and must sit
behind our own boundary (OBS-31's containment rule applied to MetricKit as well as to OTel).

**E4 — ambient platform state sampled at every wake.** `backgroundRefreshStatus`, Low Power
Mode, protected-data availability, network class, charging, boot identity, app version. Sampled
into the `wake` row so that the state *at the time* is known later, rather than reconstructed
from the state now.

Alongside these sits a fifth, structural piece of evidence: the pre-scheduled overdue
notification (§The escalation chain) fires without our code running. **If it fires, the OS is
alive and simply has not run us** — which is the cleanest possible discrimination between
"scheduling" and "device off", obtained for free from a mechanism we needed anyway.

### The decision procedure

Evaluated by the watchdog per destination over the window `[last_success_at, now]`, first match
wins. `W_sys` = system-triggered wake rows in window; `Rn` = runs started; `Sub_elapsed` =
submissions whose earliest date has passed unserviced.

| # | Condition | `attribution` | `attribution_detail` | Confidence | Remediation direction |
|---|---|---|---|---|---|
| 1 | `Rn > 0` and the most recent terminal run is a failure/partial/unknown outcome | `execution` | from `error_class` | evidenced | The named fix for that error class |
| 2 | `Rn > 0`, all runs succeeded, yet `last_success_at` is stale | `execution` | `internal_inconsistency` | evidenced | **A defect in us.** Raise; a test asserts this never fires |
| 3 | `W_sys > 0`, every wake bailed with `bailed_locked` | `execution` | `environment_locked` | evidenced | "iPhone must be unlocked. This is an Apple restriction." No action |
| 4 | `W_sys > 0`, every wake bailed with `bailed_no_network` / `bailed_budget` | `execution` | `environment_network` / `environment_budget` | evidenced | Usually none; persistent → `Constrained` |
| 5 | `W_sys = 0` and `bg_refresh_status ≠ available` | `scheduling` | `bg_refresh_denied` | evidenced | The exact Settings path |
| 6 | `W_sys = 0` and Low Power Mode observed at ≥ half of foreground samples in window | `scheduling` | `low_power_mode` | evidenced | Explain; offer Shortcuts for determinism |
| 7 | `W_sys = 0`, previous `process_instance.clean_exit = false`, no MetricKit crash/jetsam evidence for that window | `scheduling` | `force_quit_suspected` | **inferred** | "This can happen if the app was force-quit from the app switcher" |
| 8 | `W_sys = 0`, MetricKit reports repeated memory-limit or task-assertion exits | `scheduling` | `observer_backoff_suspected` | inferred | We may be in HealthKit's post-three-failure backoff; offer a re-registration action |
| 9 | `W_sys = 0`, `Sub_elapsed > 0`, none of the above | `scheduling` | `os_never_woke` | evidenced | "iOS has not run this app in the background since Tuesday." Offer Export now, Shortcuts, widget |
| 10 | `W_sys = 0`, `Sub_elapsed = 0` | `scheduling` | `not_scheduled` | evidenced | **Our defect** — we never asked. Raise |

**Confidence is a first-class output.** `evidenced` claims are stated as fact
("Background App Refresh is off for this app"). `inferred` claims are stated as possibility
("This can happen if…"). This is the same discipline R-60 imposes on the denied-vs-absent
HealthKit case, applied to scheduling, and it is what keeps RK-4 — users blaming us for Apple's
ceiling — from becoming users being told a confident falsehood by us.

**Attribution extends to staleness, not only to runs.** The reliability design names the two
staleness states this procedure produces, and they are the right names:
`stale_platform_attributable` (the device was off, locked or force-quit for the whole interval,
or Background App Refresh is disabled) and `stale_ours_or_destination` (we had opportunities and
did not deliver). Only the second is an alarm. The first still surfaces — "we cannot tell you
whether your data is flowing" is itself the news — but it accuses nobody. In this design, the
first is `attribution = scheduling` plus rules 3–4's environment cases, and the second is
`attribution = execution` with a non-environment detail; the mapping is mechanical, which is
what stops the two documents from drifting.

**Why misattribution is expensive.** Telling a self-hoster their export is failing when iOS
simply has not woken us sends them to debug a server that is working, and it is the single
most common way this product could waste someone's evening. The remediation text for
`scheduling` never mentions the destination, and the remediation text for `execution` never
mentions Background App Refresh. That separation is testable and is a required assertion.

**The observer-completion self-check.** HealthKit stops background delivery entirely after
three unanswered observer completion handlers. Every completion call writes an
`observer_completion_called` event; a run that ends without one writes nothing, and the sweep
can see the gap. Three such gaps put the destination into `attribution_detail =
observer_backoff_suspected` and offer a re-registration action. We cannot query HealthKit's
backoff state, so this is inference from our own behaviour — which is the only evidence
available and is better than none.

---

## The escalation chain

R-23: in-app indicator → local notification (if permitted) → status widget, degrading
gracefully when notification permission is absent, with the notification rescheduled on every
success so that silence becomes an event. All three rungs read the same state
(`destination_state`) so that UX-34 holds by construction.

### Rung 1 — the in-app indicator

Always available; cannot be denied; requires the user to open the app. Surfaces: the Status
screen attention row, the destination-list glyph, and the app-icon badge.

**The badge is not a fallback.** Badge display is part of `UNAuthorizationOptions` — if
notifications are denied, the badge is denied with them. This is the fact that makes the widget
load-bearing, and it is exactly why the PRD promoted the widget from Should to Must. Any Stage 3
plan that treats "we'll still show a badge" as the degradation story is wrong.

State: driven directly by `destination_state.state`. Refreshed on foreground, on any terminal
run, and on a foreground watchdog evaluation (which is also the catch-up path when background
execution is entirely denied — the watchdog must fire on foreground, not only on wakes).

### Rung 2 — the pre-scheduled local notification

The mechanism, precisely, because this is the only failure detector that survives total
background starvation:

- **One pending request per destination**, identifier `overdue.<destination_id>`, thread
  identifier `dest.<destination_id>` so repeats collapse.
- **Trigger type: interval, not calendar.** `UNTimeIntervalNotificationTrigger` with
  `repeats: false` and interval = `overdue_threshold_s − (now − last_success_at)`. An interval
  trigger is measured by the system against its own timer and is therefore immune to time-zone
  changes and to the user moving the wall clock, both of which would perturb a calendar trigger.
  Thresholds are always durations, never calendar quantities, so DST transitions cannot move
  them.
- **Reschedule is an `add` with the same identifier**, which replaces the pending request
  atomically from our point of view. Explicit `remove` is used only on destination delete,
  pause, disable, or notification-policy version change.
- **When we reschedule:** in the post-commit callback of any terminal run whose outcome is
  `success` or `success_nothing_due`. Nothing else re-arms it. A `partial`, `unknown_ack`,
  `failed`, `abandoned_no_budget` or `cancelled_by_system` run leaves the existing pending
  request in place — so a destination that keeps running and keeps not delivering still goes
  overdue on schedule. This is the property that makes silence an event: only *confirmed
  progress* defers the alarm.
- **Self-healing, not event-perfect.** A single function reconciles the desired set of pending
  requests (computed from `destination_state`) against `getPendingNotificationRequests()`. It is
  called at launch after the sweep, at every foreground, after every terminal run, after any
  destination configuration change, after a notification-settings change, after a detected clock
  anomaly, and at the end of every background wake. This costs a handful of requests and it
  means no single missed event can leave the chain silently unarmed — the failure mode that
  would quietly delete our headline capability.
- **On fire:** the notification carries status, destination label and the error's ① title only.
  Never a health value (Lock Screen, Watch mirroring). It deep-links to the destination's
  status. On the next launch we observe that the fire time has passed and re-arm at
  `now + 24 h` if staleness persists, so a permanently broken destination nags daily rather than
  hourly (UX-36: max one per destination per 24 h).
- **Fatigue backstop:** after 7 consecutive daily overdue notifications with no interaction, back
  off to weekly and say so in the app. A muted app is a dead escalation chain, so the backoff is
  a reliability control, not a courtesy.

**Permission timing** follows UX-35: `.provisional` at first destination setup (grants
immediately, delivers quietly with Keep/Turn-off), full authorisation requested in context after
a real failure, never speculatively — because a denied full prompt destroys provisional too.

**Across app updates.** Pending requests belong to the app record and survive an update; the
binary changing does not cancel them, and an update does not launch the app, so a
previously-scheduled overdue notification still fires. That is the behaviour we want. The
hazard is stale copy or a changed threshold, so each request carries a
`notification_policy_version` in its `userInfo`, and reconciliation replaces any request whose
version differs from the current build's.

**Across device restart.** Pending requests are persisted by the system and are restored across
reboot. A request whose fire time elapsed while the device was powered off is delivered late or
not at all — so the notification is never the *only* detector: the watchdog re-evaluates at
launch and the widget's timeline (below) covers the same ground independently. The two
mechanisms have disjoint failure modes on purpose.

**Across time changes.** Durations come from the monotonic clock. Freshness age is wall-clock
but corroborated: when the wall-clock delta and the uptime delta disagree by more than five
minutes, the evaluation is marked `clock_uncertain` and **we prefer the larger elapsed
estimate**. A false "stale" costs the user one app launch; a missed alarm is the category's
defining failure. Erring loud is the correct direction for this product and it is stated here so
that a Stage 3 engineer does not "fix" it in the other direction. A backwards jump that would
make `last_success_at` sit in the future is clamped, recorded as `clock_anomaly`, and rendered
as "clock changed" rather than as a negative age.

### Rung 3 — the status widget

**The widget's timeline is a pre-computed escalation schedule.** This is the design point that
makes the widget a genuine no-execution detector rather than a display of stale state. When a
timeline is generated, it contains not one entry but the sequence of *known future transitions*
derived from `destination_state`:

| Entry at | Renders |
|---|---|
| now | current state |
| `last_success_at + stale_threshold_s` | `Stale` |
| `last_success_at + overdue_threshold_s` | `Overdue` |
| +24 h, +48 h | `Overdue`, age growing |

WidgetKit renders these on schedule with no execution by the app, so if the app is never woken
again the widget still turns stale and then overdue, on its own, at the right times. Relative
age is rendered with a self-updating relative date style so the widget does not need a timeline
reload merely to tick, which keeps us well inside WidgetKit's daily refresh budget. A terminal
run requests a timeline reload from the post-commit callback; if that call never happens, the
pre-computed entries are already correct.

**Data path: the snapshot file, not the database.** The widget extension reads a small,
versioned status snapshot in the App Group container, written atomically in the same
post-commit callback that rewrites `destination_state`. Three reasons: a widget timeline
request must never block on a write lock held by a background export; the widget must render
correctly while the database is mid-transaction; and the snapshot has a tiny fixed schema
(destination pseudonym-or-label, state enum, `last_success_at`, thresholds, next-attempt
window, attribution enum) which contains no health values *structurally*, so the widget cannot
leak one even under a defect. Protection class matches the journal. The cost is a second
representation that could diverge; the mitigation is that it is written from exactly one choke
point and a test asserts snapshot-equals-derived-state after every transition in the twelve-state
cycle.

Rendering constraints from UX: state must be legible by SF Symbol shape and text alone, because
`accented` and `vibrant` modes strip colour; no health values ever; tap deep-links to the
destination's status.

### Degradation when notifications are denied

Detected on every foreground and after any settings change. When authorisation is `.denied`
(or `.notDetermined` after a first failure), the app enters **degraded escalation mode**:

1. A persistent Status-screen banner that does not dismiss until resolved: "Alerts are off.
   This app can't tell you when exports stop unless you add the status widget or open the app."
   It states the consequence, not the request.
2. A one-tap **Add the status widget** guidance flow, and a one-tap **Open Settings** for
   notifications. The widget flow is offered first, because it is the rung that works without
   granting us anything.
3. Rung 1 remains, but the badge does not (see above) — the banner says so.
4. **A user-owned alert path that does not need our permission**: the `Last successful export`
   App Intent (§The external monitoring signal) lets the user build a Shortcuts personal
   automation that notifies *them*, from *their* app, on a schedule they choose. This is
   genuinely graceful degradation — the capability moves to a surface the user already controls
   — and it costs nothing extra because R-27 needs the intent regardless.
5. **The Mac companion as an out-of-band rung** (Should, not Must): a paired Mac that has not
   received a job within its own overdue threshold raises a notification on macOS, where our
   iOS notification permission is irrelevant. This needs a small addition to the companion
   protocol — the expected cadence — and is flagged to the architect.

The soak criterion in R-23 is met by this chain twice over: once with zero background execution
granted (rungs 2 and 3 both fire without us running), and once with notifications denied
(rung 3 fires, rung 1 is present on next launch, and the degraded banner is asserted).

---

## Freshness target N

R-24 requires N to be a stated number, derived from the R-71 measurement, shown to the user
before they rely on it. R-71 has not run. This section specifies what N is, how it is computed
from R-71's findings, how it is presented honestly, and — the part that matters right now —
what the app does before those findings exist.

### What N actually measures

The reliability design defines this and I adopt its definition rather than publishing a second
one. Two points from it are load-bearing for everything below.

**The conditioning is part of the definition, not a caveat.** N is a distribution over intervals
in which the device was unlocked at least once, with no target while locked, because HealthKit is
unreadable while locked (C-02) and the unconditional distribution is a distribution over user
behaviour rather than over our system. This is the architect's NFR-08 and AR-16 shape.

**N decomposes into a part we own and a part we do not**, and conflating them is how the number
becomes dishonest:

- `L_obs = firstObservedAt − sample.endDate` — how old the data was when we first saw it. It
  contains Watch→iPhone sync latency, third-party apps backfilling weeks at once, and the user's
  lock/unlock behaviour. **We own none of it.**
- `L_del = ackedAt − firstObservedAt` — how long we took once the data was visible to us.
  **This is the only part we are accountable for.**

The journal must record both, which means `run_type_stat` carries `first_observed_at` alongside
its window bounds and `run_sink` carries `acked_at`. That is the schema consequence of the
definition and it is why I am restating it here rather than only citing it: "your watch took 90
minutes to sync and we delivered 40 seconds later" is a materially different sentence from "we
sat on it for 90 minutes", and the product cannot say either unless the journal separates them.

### Derivation from R-71

R-71's brief is "which types iOS silently caps at hourly, whether delivery survives Background
App Refresh off, actual observer-query wake duration". To yield N it must additionally produce a
**latency distribution**, so here is the measurement protocol I need, stated as a Stage 2 input
to a spike that has not run:

1. On REF-A and REF-B, with a scripted daily diary (reuse R-88's soak harness), write known
   marker samples at known instants across three type classes.
2. Record, per marker: landed-at, first observer wake after landing, first successful read,
   acknowledged-at, plus device state (locked/unlocked transitions, charging, Low Power Mode,
   Background App Refresh on/off, network class).
3. Report p50 / p95 / p99 of `L_obs` and `L_del` **separately**, segmented by freshness class and
   by device state, and separately report the fraction of 24-hour windows containing zero system
   wakes.
4. Report the `earliest_begin_at → serviced_at` distribution for `BGAppRefreshTask`.

From that, `N` is reported per class as a p50/p95 pair, never as a single number and never as a
mean.

### Per-type or global: neither

**Per freshness class**, assigned per type in the metric catalogue. This is the reliability
design's ADR-R9 and it is better than the three-class split I had drafted, so I have dropped
mine. Global is wrong because one number is either useless (dominated by the worst class) or a
lie (flattered by the best); per-type is wrong because ~200 numbers are unusable and most types
have too little data on any one device to estimate.

| Class | Character | Typical members | Shape of N |
|---|---|---|---|
| **A** | Phone-local, high-frequency, immediate delivery available | steps, distance, flights | minutes |
| **B** | Watch-synced; gated by Watch↔iPhone sync | heart rate, HRV, active energy, workouts | tens of minutes |
| **C** | Hourly-capped by the platform, or session-shaped and written long after the fact | sleep analysis | **hours**, stated in hours |
| **D** | Written by third-party apps or hardware on their own schedule | CGM glucose, scale weight, manual entries | **explicitly unpredictable**; publish the measured distribution, claim nothing |

The observability consequence: **the class is a journal dimension.** `run_type_stat` carries the
freshness class, the per-class distribution is computable by Q8 without a scan, and the class is
in the allowlist as a four-value enum — so it is safe in a span, safe in the bundle, and safe as
a metric dimension in a way the type identifier never is. That is a genuinely useful property:
it lets the OTLP projection and the diagnostic bundle say *"class C is 4 hours behind"* without
saying *"your sleep data is 4 hours behind"*, which is the same operational fact with the
diagnosis removed.

### Presenting it honestly

Three layers, in the app, on the destination's freshness screen, and in the README:

1. **The published per-class figure, with its condition attached in the same sentence**, and only
   until the local estimate qualifies. "Typically within *p50*, and within *p95* nineteen times
   out of twenty, when you unlock your iPhone at least once in the period. iOS decides when this
   app may run; these are measurements, not guarantees."
2. **Then the user's own number, which supersedes it.** Once a class has ≥ 14 days of observation
   and ≥ 100 samples on this device — the reliability design's qualification bar — the app
   displays that device's own measured p50 and p95, labelled as such, computed by Q8 from the
   journal at zero egress cost. The published N is a placeholder for the local estimate, not a
   claim that outlives it. This is strictly better than a published constant: it is per-device,
   self-measured, and cannot be wrong about the device it describes. It also changes what R-24
   means, which is why the reliability design raised it and why I am seconding it in Q7.
   Alongside the number, the UI shows the `L_obs`/`L_del` split, because a user whose Watch took
   90 minutes to sync deserves to know that we were not the slow part.
3. **The evidence link.** The freshness screen links to the run history filtered to that
   destination, so the claim is checkable rather than asserted. The whole product is "tells you
   the truth about what it did"; a freshness number the user cannot audit would be the one
   unfalsifiable claim in it.

Never presented: a single unconditional number, a countdown to the next export, a
"next export at HH:MM", or any phrasing implying a schedule (PC-2).

### Behaviour before the spike results exist

This is the operative part today, and the key move is to **decouple escalation from N**.

- **The escalation thresholds must not depend on a number that does not exist.** Three Stage 2
  documents currently define this threshold three different ways — UX's `stale = max(2C, 90 min)`
  / `overdue = max(4C, 6 h)` from a user-chosen cadence `C`; the reliability design's
  `clamp(2 · N_p95(class), 6 h, 48 h)`; and the architecture design's `lastSuccess + N`. They are
  not reconcilable by picking one, because the first is shippable before R-71 and the other two
  are not. **My proposal, raised as Q11: one threshold function, one owner, two regimes.**
  Pre-spike, thresholds derive from the user's chosen cadence class `C` with interim floors taken
  from Apple's *documented* caps and labelled as such. Post-spike, the same function takes
  `N_p95(class)` for the tightest enabled class and clamps it, per the reliability design's
  formula. The escalation state machine, the notification schedule and the widget timeline are
  identical under both regimes and do not change when the number arrives — only their input does.
  **On that basis the watchdog, the notification and the widget are fully specified and fully
  shippable before R-71 reports**, which is the property that matters most, because R-23 is a Must
  and R-71 is a spike that has not run.
- **Where N would be printed, print its absence.** "We don't have a measured figure for this
  yet" plus, when available, the user's own measured distribution. The README says the same and
  names R-71 as the open measurement. **No placeholder number is ever shown**, because a
  provisional number in a product whose thesis is honesty is worse than a stated gap.
- **R-24 is not met until R-71 publishes**, and the release gate must record that explicitly
  rather than accepting a fabricated figure. The PM should treat "N is unmeasured" as a
  requirement status, not as a documentation task (Q7).
- The journal is already collecting the data R-71 needs from real installs (`bg_submission`
  latency, marker-free landed→acked where a sample's HealthKit start date is known), so the
  measurement improves after ship without any egress and without any collector.

---

## Signal taxonomy and cardinality budget

The vocabularies below are declared **once**, in the allowlist manifest, and are shared by the
journal columns, the metric dimensions and the OTLP attributes. Three consumers, one source, so
they cannot drift and a new value cannot appear in one without appearing in all.

### Spans

Names come from a fixed enum; variable data goes in attributes. This is cardinality rule 1.

| Span | Kind | Parent | Purpose |
|---|---|---|---|
| `export.run` | INTERNAL | root | One run for one destination. Carries the outcome |
| `export.discover` | INTERNAL | `export.run` | Determine what is due; read anchors and high-water marks |
| `export.query` | INTERNAL | `export.run` | One HealthKit query |
| `export.transform` | INTERNAL | `export.run` | Domain mapping, aggregation (R-06) |
| `export.serialise` | INTERNAL | `export.run` | Encode to NDJSON / JSON / CSV / HAE profile |
| `export.transmit` | CLIENT | `export.run` | The network or file write. **Attributes deliberately non-conformant** |
| `export.acknowledge` | INTERNAL | `export.run` | Interpret the destination's answer |
| `export.commit` | INTERNAL | `export.run` | Advance the watermark. Separate from acknowledge **because this is where false success is manufactured** |
| `export.retry` | INTERNAL | `export.run` | One retry attempt |
| `destination.test` | INTERNAL | root | R-25's pre-enable test |
| `test.resolve` / `test.tls` / `test.authenticate` / `test.send` / `test.confirm` | INTERNAL | `destination.test` | UX-09's five named steps, so R-25's per-step reporting and the trace share one structure |
| `journal.sweep` | INTERNAL | root | Seals interrupted runs; low volume, high diagnostic value |

Fourteen names, closed. `export.commit` and the `test.*` set are deliberate additions to the
obvious taxonomy: the first because the gap between acknowledge and commit is where the
incumbent's defining bug lives, the second because R-25's acceptance criterion is per-step and
inventing a second step vocabulary for the test screen would guarantee they diverge.

### The semantic-convention deviation, restated for Stage 2

`export.transmit` is an HTTP client span, and stable HTTP semconv requires `server.address` and
expects `url.full`, `server.port`. **Those are exactly the fields that reveal which clinic, CGM
vendor or insurer a person sends their health data to.** We emit `http.request.method` and
`http.response.status_code` and omit `server.address`, `server.port`, `url.full`, `url.path`,
`url.query`, and all headers. We substitute `ohe.destination.kind` (closed enum) and
`ohe.destination.id` (opaque, random, meaningless off-device).

Consequences that must be carried into Stage 3: we cannot claim HTTP semconv conformance and
must say so in the published schema; and **`URLSessionInstrumentation` must be explicitly
disabled and asserted absent from the dependency graph**, because its entire job is to populate
the attributes we forbid. For MQTT, messaging semconv is Development status and `mqtt` is not a
registered `messaging.system` value, so there is little to conform to; we use
`messaging.operation.name` and omit `messaging.destination.name`, because **the MQTT topic
string is user-authored and routinely contains names, room names and device names**. For the
Mac companion there is no convention; we emit `ohe.destination.kind = mac_companion` and no
device name, no Bonjour service name and no host.

### Attributes

**On `export.run`:** `ohe.export.trigger` (8), `ohe.export.outcome` (7), `ohe.export.mode` (5),
`ohe.destination.kind` (4: `file`, `https`, `mqtt`, `mac_companion`), `ohe.destination.preset`
(3: `none`, `home_assistant`, `hae_profile`), `ohe.destination.id` (opaque),
`ohe.export.format` (4), `ohe.export.samples_read` / `_sent` / `_acked` / `_rejected` (counts,
never values), `ohe.export.types_count`, `ohe.ack.evidence` (8), `ohe.ack.units_total` /
`_confirmed`, `ohe.error.class` (~30), `error.type` (semconv, set from our closed enum, never
from a localised description), `ohe.attribution` (2), `ohe.attribution.detail` (9),
`ohe.attribution.confidence` (3), `ohe.device.locked_during_run` (bool),
`ohe.device.low_power_mode` (bool), `ohe.device.charging` (bool), `network.connection.type`
(semconv, 4), `ios.app.state` (semconv), `ohe.transport.security` (5),
`ohe.budget.granted_ms` / `used_ms` (numeric).

**On `export.query`:** `ohe.health.type` (Apple's closed enumeration — acceptable as a *span*
attribute for local inspection, **excluded from OTLP egress by default and from metric
dimensions by default**; see below), `ohe.query.anchored` (bool), `ohe.query.range_days`
(bucketed: 1, 7, 30, 90, 365, >365), `ohe.query.samples` (count).

**Resource:** `service.name`, `service.version`, `os.name`, `os.version`,
`device.model.identifier`. **Not** `device.id`, not IDFV, not an install UUID. `session.id` is
local-only by default and stripped from any egress unless separately enabled, because a
device-stable correlator turns anonymous telemetry into a fingerprint.

**`ohe.health.type` in egress.** The security engineer's position is that a HealthKit type
identifier *is* the diagnosis, and I agree. Default: the identifier appears in the local journal
(where it is needed for coverage and for `partial` attribution) and **never in OTLP egress or in
the diagnostic bundle**. A user-armed toggle can include it in either, off by default, with the
disclosure named in the toggle's copy and visible in the bundle preview. That toggle is the one
documented exception I am asking for, and it is Q2.

### Error catalogue

Closed, ~30 values, each with a localised one-sentence cause and one-sentence remediation
(UX's ①②③④ schema). **The journal has no free-text error column**, so a raw `NSError`
description cannot reach the journal, the bundle, the UI or a span even by accident — SEC-38's
V-4 enforced by schema rather than by discipline.

`healthkit_locked`, `healthkit_unauthorized`, `healthkit_no_data`, `healthkit_query_timeout`,
`healthkit_partial_read`, `transform_failed`, `serialise_failed`, `transport_dns`,
`transport_tls_trust`, `transport_tls_pin_changed`, `transport_tls_handshake`,
`transport_timeout`, `transport_refused`, `transport_plaintext_blocked`,
`transport_http_400`, `transport_http_401_403`, `transport_http_404`, `transport_http_413`,
`transport_http_429`, `transport_http_5xx`, `mqtt_unreachable`, `mqtt_not_authorised`,
`mqtt_publish_failed`, `companion_unreachable`, `companion_rejected`,
`companion_version_mismatch`, `file_permission_denied`, `file_bookmark_stale`,
`file_no_space`, `ack_absent`, `ack_rejected`, `budget_exhausted`, `queue_full`,
`config_invalid`, `unclassified`.

Three of these are new since Stage 1 and exist because scope changed: the companion trio, and
`file_bookmark_stale` — a security-scoped bookmark going stale is a real and common way a
file destination silently stops working, and it is precisely the kind of failure that would
otherwise present as "nothing happens".

### Metrics and the cardinality budget

**Metric dimensions use a coarsened projection of the span vocabulary.** Spans are not
aggregated and can afford `trigger` at eight values; a metric cannot, so metrics use
`trigger.class ∈ {user, system_observer, system_scheduled, other}`. This is the single technique
that keeps the budget honest without losing the diagnostic value, and it is stated as a rule so
that Stage 3 does not "simplify" it by unifying the two.

| Metric | Type | Unit | Dimensions | Series |
|---|---|---|---|---|
| `ohe.export.runs` | Counter | `{run}` | trigger.class(4) × kind(4) × outcome(7) | 112 |
| `ohe.export.duration` | Histogram | `s` | kind(4) × phase(8) | 32 |
| `ohe.export.errors` | Counter | `{error}` | error.class(28) × kind(4) | 112 |
| `ohe.export.samples` | Counter | `{sample}` | kind(4) × direction(4) | 16 |
| `ohe.export.payload.size` | Histogram | `By` | kind(4) × format(4) | 16 |
| `ohe.export.retries` | Counter | `{attempt}` | error.class(28) | 28 |
| `ohe.destination.staleness` | Gauge | `s` | destination.id(≤8) | 8 |
| `ohe.destination.last_success.timestamp` | Gauge | `s` | destination.id(≤8) | 8 |
| `ohe.background.wake` | Counter | `{wake}` | trigger.class(4) × disposition(6) | 24 |
| `ohe.healthkit.query.duration` | Histogram | `s` | — (+ health.type opt-in) | 1 |
| `ohe.telemetry.dropped` | Counter | `{item}` | signal(3) × reason(6) | 18 |
| `ohe.journal.bytes` / `ohe.journal.rows` | Gauge | `By` / `{row}` | — | 2 |
| | | | **Total, default** | **377** |

With `health.type` enabled (curated families capped at 64 with overflow to `other`):
`ohe.export.samples` 16 → 1,024 and `ohe.healthkit.query.duration` 1 → 64, total ≈ **1,448**.
Both inside the Stage 1 budgets (≤ 500 default, ≤ 2,500 enabled), and now with the arithmetic
shown rather than asserted.

**The rules, unchanged from Stage 1 and restated because they are the enforcement surface:**

1. Every metric attribute value comes from a compile-time-closed enumeration. There is no path
   by which a runtime string becomes a dimension value.
2. A runtime guard replaces an unrecognised value with `other` and increments
   `ohe.telemetry.dropped{reason="unknown_attribute_value"}`. Fail-safe, not fail-open.
3. **Never a dimension, and never a span attribute:** sample UUID, sample value, sample
   timestamp, hostname, URL, port, MQTT topic, Bonjour service name, file path,
   security-scoped bookmark, user-authored destination label, `HKSource` or device name, OS
   error code, error message, `session.id` (metrics), trace/span IDs (metrics).
4. `ohe.destination.id` is bounded: destinations beyond the eighth collapse to `other` for
   metric purposes. Spans keep the real opaque id.
5. Histogram bucket boundaries are fixed at declaration and never derived from data.
6. **A build-time test enumerates the declared cross-product and fails the build above the cap.**
   This is what stops the budget from being a paragraph nobody reads.

### Log events

Two distinct things, and conflating them is the trap:

- **`os.Logger` output** — free-form, privacy-annotated, current-process only, never exported,
  not a stable contract. Dynamic string interpolations are `%{private}` by default, which means
  that when the current process's entries are read back via `OSLogStore` for the diagnostic
  bundle, **the OS itself has already redacted them to `<private>`**. That is a concrete payoff
  of R-50's `os.Logger`-over-`swift-log` decision and it is worth naming, because it is the only
  place in the stack where the platform gives us privacy-by-default for free. `Enable-Private-Data`
  must never appear in a release build's `OSLogPreferences`; a CI check asserts it.
- **Journal events** (`run_event`) — closed schema, durable, versioned, the thing that becomes
  OTel span events. Because OTel Logs in Swift remains beta quality, v1 maps journal events to
  **span events on the run span**, not to the OTel Logs API — more mature, and semantically
  honest, since they *are* events within a run.

---

## The OTLP projection

R-53 is a Should. If v1 sheds scope, this section is what goes, and nothing above it changes.

### The central decision: projection, not instrumentation

**No span objects are constructed during an export run.** The run writes journal rows it would
have written anyway. A separate projector, running later, reads runs with `projected_at IS NULL`
and emits OTLP. Five consequences, all good:

1. **R-79 (≤ 2% of the wake budget) is met by construction.** Telemetry work during a background
   wake is zero, not small. The only run-time cost is generating a 16-byte trace ID and an
   8-byte span ID at run start, which we do unconditionally because `traceparent` (R-54) and the
   history Evidence field need them whether or not OTLP is on.
2. **"Telemetry survives process death" is free**, because the journal already does. We do not
   need `BatchSpanProcessor`, and we do not need the SDK's `PersistenceSpanExporterDecorator` —
   whose reference implementation stores under `.cachesDirectory`, which the system may purge.
   One less moving part and one less silent data-loss path.
3. **Cold start is unaffected.** No OTel type is touched during launch, and telemetry
   initialisation cannot precede `HKObserverQuery` registration in `didFinishLaunching` because
   it does not happen at launch at all. Asserted by a test that fails if any OTel symbol is
   referenced on the launch path.
4. **The projection is replayable.** A user who enables OTLP today can backfill the last 30 days
   of runs into their collector, which is a genuinely nice self-hoster property and falls out for
   free.
5. **The journal outranks OTLP structurally**, not just in priority order. If the projector is
   broken, deleted, or the SDK breaks on an upgrade, the product loses nothing.

### The mapping

| Journal | OTLP |
|---|---|
| `run` row | root span `export.run`, `trace_id`/`span_id` from the row, start/end from the uptime pair converted to absolute, attributes from the run's allowlisted columns |
| `run_phase` row | child span, name = phase |
| `run_event` row | span event on the run span, name = event enum, attributes from the typed numeric slots |
| `run_type_stat` row | **not projected by default** (privacy and cardinality); projected as bucketed counts only when the `health.type` toggle is on |
| `destination_state` | the two gauges, `ohe.destination.staleness` and `ohe.destination.last_success.timestamp` |
| `wake` row | span `journal.sweep` context or a counter increment; not a span per wake |

Attribute selection is **manifest-driven**: the projector iterates the allowlist manifest's
`otlp`-sinked entries, not the row's fields. A new journal column projects nothing until it is
added to the manifest.

### Export path and buffering

- **Transport: OTLP/HTTP + protobuf only.** No gRPC, no `grpc-swift`, no SwiftNIO in any app
  target, asserted by a dependency-graph check. The trade is recorded honestly: the SDK marks
  HTTP as the less mature transport, and I am choosing it on dependency-weight grounds with the
  mitigation that the feature is opt-in and non-default, so a transport bug degrades an opt-in
  capability rather than the product.
- **Endpoint is user-supplied**, is an entry in the R-32 destination allowlist, appears in the
  destination list as a first-class revocable entry, and its egress is recorded in the R-30
  ledger and in history (OBS-24). TLS required except for RFC1918 / link-local / `.local` /
  loopback under SEC-20's typed acknowledgement, address class re-checked at connect time on
  every connection.
- **Opportunity policy:** foreground with network; or charging on Wi-Fi under a `BGProcessingTask`
  submitted *for telemetry*, never piggybacked on an export wake. Never during an observer-query
  wake. Never before an observer completion handler. Telemetry export generates no telemetry
  (no recursion) and runs on an isolated pipeline with its own serialiser, sharing no code with
  health-payload serialisation — an architecture test asserts no shared serialisation type.
- **Batching and backlog:** bounded by count and bytes per request; exponential backoff with
  jitter; backlog capped at 5,000 unprojected runs or 30 days, oldest-dropped, every drop
  counted in `ohe.telemetry.dropped{reason="backlog_cap"}` and visible in the app. At-least-once
  delivery; duplicates are harmless because trace and span IDs are stable, so the collector
  converges.
- **Preview before enabling:** the literal bytes of a representative export, on screen,
  scrollable, copyable — the same discipline as the diagnostic bundle, for the same reason.
- **Published, versioned attribute schema** in the repository listing every attribute we can
  ever emit, its type, its domain and whether it is health-derived. A CI conformance test
  asserts the emitted attribute set is a subset of the published schema. Auditability by the
  people whose data it is, is the thing "genuinely open source" is supposed to buy.

### R-54 — `traceparent` propagation

Per-destination opt-in, default off. `tracestate` and `baggage` are **never** sent. An inbound
`traceparent` is **never** continued (we have no listener on iOS, and the Mac companion must
start a new root rather than adopt a caller's trace — naively continuing a trace with the
sampled flag set is a denial-of-monitoring vector, and on a battery-powered device that is also
denial-of-battery).

The header's trace ID is the run's trace ID, so a self-hoster's server-side span joins the
phone-side `export.transmit` span in one trace and answers "the phone says it sent 400 samples
and my server says it got 12". That is the one capability OTel provides here that nothing else
can.

**Auto-disable on evidence of breakage**, specified precisely because "propagation must never
turn a working export into a failing one" needs a mechanism, not an intention: on a request
failure whose class is header-plausible (400, 431, 403, or a connection reset before response),
retry once within the same run *without* the header. If that retry succeeds, disable propagation
for that destination, write a `traceparent_auto_disabled` journal event, and surface a history
entry naming what happened and how to re-enable. Applies to HTTPS and to the Mac companion
(which carries it as an explicit protocol field); MQTT has no header and the option is not
offered.

Note that propagation is independent of OTLP export: a user may opt into `traceparent` with no
collector configured, which is harmless and occasionally useful if their server logs it.

---

## Redaction allowlist and the diagnostic bundle

### The allowlist mechanism (R-51)

Four layers, from strongest to weakest. The strength ordering matters: each layer exists because
the one above it cannot cover everything.

**Layer 1 — structural impossibility.** The journal has no free-text column and no column that
can hold a hostname, a URL, an MQTT topic, a file path or a user-authored label. It holds
`destination_id`; the human label lives in the configuration store and is joined **at render
time for the UI only, and never for any artefact that leaves the device**. Health values are not
representable in any journal or telemetry type (SEC-43's V-9). A regex scrubber at the sink is
explicitly not the mechanism, because it fails silently on new fields.

**Layer 2 — the declared manifest.** One machine-readable file, CODEOWNERS-protected, listing
every attribute the product can emit:

| Field | Meaning |
|---|---|
| `key` | The attribute or column name |
| `type` | numeric / bool / enum / opaque-id / bucketed |
| `domain` | The closed value set, or the bucket boundaries, or the numeric range |
| `sinks` | Any of `journal`, `ui`, `bundle`, `otlp`, `notification`, `widget` |
| `health_derived` | bool — a declared property, reviewed |
| `justification` | One line, argued in the diff that adds it |

Per-sink permissions are the important part: `ohe.health.type` is `journal, ui` and not
`bundle, otlp`. A field is absent from a sink unless explicitly permitted for that sink.

**Layer 3 — manifest-driven emission.** The bundle serialiser and the OTLP projector iterate the
manifest, not the record. **A new journal column is invisible to both until someone adds it to
the manifest**, which makes the default deny structural rather than procedural. This is the
single most important mechanical property in this section: it converts "did anyone check?" into
"the diff shows it".

**Layer 4 — CI enforcement.** Four jobs, on every commit:

1. **The canary.** Fixtures seed: a bearer token, `clinic.example.org`, sample value `42.7`,
   source name `Dexcom G7`, container path `/var/mobile/Containers/...`, MQTT topic
   `home/bedroom/glucose`, Bonjour name `Colins-MacBook-Pro.local`, `192.168.1.50`, an IPv6
   literal, a security-scoped bookmark blob, the label `Dr Patel's server`, and
   `HKCategoryTypeIdentifierSexualActivity`. Every emitted artefact — bundle, OTLP payload,
   widget snapshot, notification payload, `os.Logger` output for the current process — is
   asserted free of each canary **in raw, percent-encoded, base64, JSON-escaped, UTF-16 and
   gzip-decompressed forms**. Encoded-form matching is what naive canaries miss and it is where
   a real leak would hide.
2. **Manifest exhaustiveness.** Every journal column and every emittable attribute key must
   appear in the manifest; the build fails on any unmapped key. Every manifest domain is
   enforced at runtime (out-of-domain → `other` + dropped counter), asserted by a test.
3. **The canary of the canary.** A job that deliberately introduces a leak through a test-only
   fixture and asserts that job 1 *fails*. Without this, a canary that silently stops asserting
   passes forever, and RK-5 says quiet erosion is the default outcome, not the tail case. This
   job is cheap and it is the difference between a control and a comforting green tick.
4. **Egress inventory.** A string scan over the built product asserting no
   maintainer-controlled hostname and no ingest credential exists anywhere (R-55), plus a
   `PrivacyInfo.xcprivacy` check asserting `NSPrivacyTracking = false` and no
   `NSPrivacyTrackingDomains` (R-52).

### The diagnostic bundle (R-26)

**Contents**, all manifest-derived:

| Section | Contents |
|---|---|
| Header | Bundle schema version, app version, OS version, device model identifier, locale, UTC offset, generated-at, `degraded[]` flags |
| Configuration shape | Per destination: pseudonym (`destination-1`), kind, preset, format, transport security class, plaintext opt-in flag, cadence class, count of selected types **by family**, sensitive-class-enabled boolean. **No labels, no hosts, no topics, no paths, no credentials, no type identifiers** |
| Runs | Last 200 runs, every `bundle`-sinked column, per-phase timings, per-type-**family** counts |
| Wakes and submissions | The wake ledger and scheduling-latency records for the window |
| Attribution | Current attribution per destination with confidence |
| Metrics | The cardinality-capped snapshot |
| MetricKit | `MXCrashDiagnostic` / `MXHangDiagnostic` call-stack trees and `MXAppExitMetric` summaries — Apple-generated, our symbols, no user data |
| Logs (optional, off) | Current-process `os.Logger` entries; see below |

**Format.** A single UTF-8 JSON document with a published, versioned schema, targeted at
≤ 200 KB so it can be *pasted* into a GitHub issue — a ZIP only above the cap. Making the
bundle pasteable is a deliberate answer to the Stage 1 risk that non-technical users cannot get
one to a maintainer.

**The log section is off by default and it is the one part that is not allowlist-governed.**
Free-form log text cannot be governed by an allowlist by definition. It gets three defences:
`os.Logger`'s `%{private}` default means the OS has already redacted dynamic strings when we
read them back; a shape-based filter rejects entries containing an IP literal, a
hostname-shaped token, a ≥20-character base64/hex run, a container path, or a number adjacent to
a unit token; and it is **opt-in per bundle, never sticky, and rendered in the preview**. That
filter is a denylist, and I am labelling it as one: it is defence in depth over an optional
section, not the mechanism, and the mechanism (layers 1–3) governs everything structured.

**The preview gate (R-26 / OBS-08).** The share affordance is not disabled — it **does not exist
in the view hierarchy** until the preview's full content has been reached. A disabled-but-present
button is still reachable by VoiceOver, so "disabled" is not a gate. The automated assertion is
therefore existence-based, not enabled-state-based, and it includes an accessibility-tree
assertion. For parity with assistive technology and accessibility text sizes, "reached the end"
is satisfied either by scrolling to the end or by an explicit "I have read this" confirmation
that is itself only reachable at the end of the content (R-64).

Two reasons this gate is worth its friction, and only one of them is consent: it makes consent
contemporaneous and unambiguous, which is what lets R-55 hold; and it turns the entire user base
into a redaction-bug detector, which will find holes our canary corpus does not contain.

**Working when the app is broken (OBS-09).** Bundle generation must succeed with no network,
with HealthKit authorisation revoked, with an invalid destination configuration, and with a
partially corrupt journal. It therefore does not go through the export pipeline, opens its own
read-only connection, runs an integrity check first, and falls back to row-by-row salvage of the
`run` table on failure — emitting a partial bundle with an explicit `degraded[]` header naming
what could not be read and how many rows were skipped. A diagnostic that needs the subsystem it
is diagnosing is unavailable exactly when it is needed.

**Sharing** is via the share sheet to Files, Mail, Messages or a browser. Never auto-uploaded.
Never to a maintainer-controlled host — there is none (R-55).

---

## The external monitoring signal

R-27: "time since last successful export" consumable by the user's own monitoring, with a
documented failure taxonomy. Its acceptance criterion was deliberately decoupled from the
reference receiver (R-115) and the HACS integration (R-116), both Shoulds, so **the design must
stand up with neither of them built**. Four surfaces, ordered by how little they depend on.

### S1 — the App Intent (the load-bearing surface)

`Last successful export` is an App Intent, exposed to Shortcuts, returning per destination:
label, `last_success_at` (ISO 8601 with offset), `last_confirmed_ack_at`, `age_seconds`,
`state`, `last_outcome`, `attribution`, `attribution_confidence`, `error_class`.

This is the surface that satisfies R-27 alone, because it needs nothing but the app: a user
builds a Shortcuts personal automation ("every day at 09:00, if age > 6 hours, notify me") with
no server, no collector, no integration and no permission from us. It is also the
notification-denied fallback from §The escalation chain, so one mechanism discharges two
requirements.

### S2 — the status record written to the user's own destination

The most valuable surface for the self-hoster, and the only one that detects a phone that is
**off, dead, lost or restored to factory** — because in that case nothing on the device can
notice anything.

On every run, including `success_nothing_due`, the exporter writes a small status record over
the same transport, alongside the data:

| Field | |
|---|---|
| `schema_version` | Frozen under R-12's stability commitment |
| `exporter_instance_id` | Stable per install, opaque |
| `run_seq`, `run_at` | |
| `last_success_at`, `last_confirmed_ack_at`, `age_seconds` | |
| `outcome`, `attribution`, `attribution_confidence`, `error_class` | |
| `samples_read` / `_sent` / `_acked` / `_rejected` | |
| `cadence_class`, `stale_threshold_s`, `overdue_threshold_s` | So the receiver can alert on our own thresholds |

Contains **no health values**, so it is safe to make more widely readable than the data itself.

Per destination type:

- **HTTPS:** a `_status` object in the envelope defined by the wire spec, plus an optional
  separate status endpoint for users who want it isolated.
- **MQTT:** a **retained** message on `<base>/status`. A retained status message means any
  subscriber immediately receives the latest value with its age, and Home Assistant's native
  `expire_after` on an MQTT sensor marks the entity unavailable when it stops arriving. That is
  a documented, zero-custom-code alert path for the primary persona, and it is why this surface
  beats OTLP for P1.
- **Local file:** `status.json` written atomically next to the data. Its mtime and contents are
  watchable by cron, Node-RED, Telegraf or a Grafana file datasource.
- **Mac companion:** the companion holds the last receipt and its expected cadence, and can
  raise its own macOS notification when it goes overdue.

### S3 — widget and Control Centre

Human-consumable, covered in §The escalation chain.

### S4 — OTLP gauges (Should)

`ohe.destination.staleness` and `ohe.destination.last_success.timestamp`, for users who already
run a collector. Genuinely valuable, and explicitly *not* the acceptance path for R-27.

### The documented failure taxonomy

Published in the repository as a versioned table, with stable machine identifiers so that users'
alert rules do not break across our releases. Columns: `outcome`, `attribution`,
`error_class`, severity, "is this actionable by the user", and the recommended alert action.
Three rows illustrate why the taxonomy earns its keep:

| Signal | Recommended action |
|---|---|
| `age_seconds > overdue_threshold_s` | Alert. Something has stopped |
| `outcome = unknown_ack` sustained over 24 h | Investigate — likely MQTT QoS 0. Do not treat as delivery |
| `attribution = scheduling`, detail `os_never_woke`, sustained | **Do not page.** iOS has not run the app; no server-side action will help |

That last row is the taxonomy's real purpose. A monitoring signal that pages a self-hoster
about something they cannot fix trains them to ignore it, and then the honest product has
manufactured the very silence it exists to prevent.

Documentation ships with a worked example for a Prometheus/Grafana alert rule and an alert
based on MQTT `expire_after`, both written against the status record, neither depending on
R-115 or R-116.

---

## Verification: how each requirement is tested

| Req | Method | Fails when |
|---|---|---|
| **R-20** | Fault-injection matrix: SIGKILL at each of the 9 phase boundaries × 5 destination kinds; relaunch; assert the sweep seals every run, the journal is readable, no row is orphaned, and totals reconcile with the queue. Repeated across a simulated OS upgrade and an app update in the release check | Any orphaned in-flight row, any unreadable journal, any outcome assigned by rule 11 |
| **R-21** | Force every outcome. Integration test with a destination that accepts the connection and silently discards the body → asserts `partial` or `unknown_ack`, never `success`. Property test: for 10,000 random count tuples, the procedure is total and rule 7 never fires with `A < R`. Plus the database CHECK constraint | Any `success` with `samples_acked < samples_read`; any run left without an outcome |
| **R-22** | Simulate zero system wakes over a window → asserts `scheduling` / `os_never_woke`; simulate wakes that all fail → asserts `execution`; assert the two remediation strings share no substring and that `scheduling` copy never mentions the destination. Assert `attribution_confidence = inferred` for force-quit and backoff cases | Misattribution in either direction; a confident claim on inferred evidence |
| **R-23** | Soak with export deliberately broken, three configurations: (a) zero background execution granted — asserts the pre-scheduled notification fires and the widget timeline transitions without app execution; (b) notifications denied — asserts widget escalation, the degraded banner, and that no badge is claimed; (c) both. Plus reboot, app-update, forward and backward clock-change, and time-zone-change cases against the reschedule reconciler | Silence beyond the overdue threshold in any configuration |
| **R-24** | R-71's findings document must exist and establish the four class boundaries and their p50/p95 distributions; the figures must appear in-product and in the README; the app must render the device's own distribution once a class qualifies (≥ 14 days, ≥ 100 samples) and must show the `L_obs`/`L_del` split. Before the spike: assert that **no numeric N is displayed anywhere** | A placeholder number shipping; N present without R-71; a published constant still shown after the local estimate qualifies |
| **R-25** | Bogus host per destination kind → destination cannot be saved enabled; per-step failure attribution correct for 15 induced conditions; MQTT QoS 0 publish with no subscriber → `Sent, unconfirmed`, never success | Any protocol producing `success` without confirming evidence |
| **R-26** | Existence-based UI assertion that no share affordance is in the view hierarchy or the accessibility tree before the preview end is reached; a maintainer diagnoses a seeded failure from the bundle alone; the canary suite; the four OBS-09 fault cases each yield a well-formed degraded bundle | A reachable share affordance; any canary present in any encoding |
| **R-27** | The App Intent returns correct values with no network and no collector; a Shortcuts automation built from it fires; the status record appears on each destination kind, is retained on MQTT, and drives an `expire_after` alert in a real HA instance; the taxonomy table is published and versioned | R-27 passing only because R-115 exists |
| **R-50** | Dependency assertion: no `swift-log` in any app target. ADR recorded. Lint flags `privacy: .public`. CI asserts no release Info.plist contains `Enable-Private-Data` | Any of the above |
| **R-51** | The four CI jobs above, on every commit, including the canary-of-the-canary | A leak in any encoding; an unmapped key; a canary that no longer fails on a seeded leak |
| **R-52** | Network-isolation test: full export cycle in default configuration with a loopback interceptor → zero telemetry-attributable connections. Static `PrivacyInfo.xcprivacy` check | Any egress in default configuration |
| **R-53** | Recording-collector fixture receives the projected spans; disabling produces zero egress; launch-path assertion that no OTel symbol is referenced during `didFinishLaunching`; wake-budget instrumentation asserts 0 ms of telemetry work during a background wake (stronger than R-79's ≤ 2%) | Telemetry on the launch path or in a wake |
| **R-54** | Default config sends no trace headers (capturing server); enabled config sends `traceparent` only, never `tracestate`/`baggage`; a header-rejecting server triggers auto-disable with a history entry; an inbound `traceparent` at the Mac companion yields a new root trace | Any header sent by default; propagation able to break a working export permanently |
| **R-55** | String scan over the built product for any maintainer-controlled hostname or ingest credential; ADR recorded | Any such string existing |
| SLO-7 | On-device performance test: ≤ 5 MB journal at default retention, ≤ 0 ms added to a background wake, ≤ 30 ms added cold start, 0 bytes network in default configuration | Any breach; release-gating |

---

## Open questions for the PM

**Q1 — User-cancelled runs.** R-21's outcome set is closed and I will not add an eighth value.
My proposal is `cancelled_by_system` with a `cancel_source ∈ {system_budget, user,
os_termination}` discriminator, which keeps the PRD's enum exact while letting the UI say
"Cancelled" rather than blaming iOS for something the user did. This is real: R-11's full
backfill under `BGContinuedProcessingTask` has explicit user cancellation. **Needs ratification
so it is a decision, not a Stage 3 improvisation.**

**Q2 — HealthKit type identifiers in the diagnostic bundle.** The security engineer refuses type
identifiers in any artefact, correctly: `bloodGlucose` is the diagnosis. But diagnosing "my
sleep export is truncated" from a bundle without type names is materially harder. I propose a
**user-armed, off-by-default, non-sticky, per-bundle toggle**, with the disclosure named in the
toggle copy and the identifiers visible in the mandatory preview. This is a documented exception
to V-3 and needs the security engineer's sign-off and a recorded owner, not my unilateral call.

**Q3 — History does not migrate.** Backup exclusion (SEC-30, OBS-33) means export history and
the freshness clock do not survive device migration. I think that is the right trade and I have
designed the restore case to show `Never run` rather than a false `Healthy`. Confirm, and
confirm the copy that tells the user.

**Q4 — Ledger growth and the never-prune position.** ~1.3 MB/year at three destinations, ~6.5 MB
over five years, never compacted because compacting a tamper-evidence record is
tamper-adjacent. Confirm with the security engineer that "publish the growth rate" is the right
answer rather than a cap.

**Q5 — The journal/ledger transaction coupling.** I propose the ledger row commits in the same
transaction as the run's terminal record, with a foreign key between them, so they can never
disagree. This touches R-30, which the security engineer owns. Confirm ownership of the coupling.

**Q6 — Localisation scope for the error catalogue.** ~35 error classes × two sentences each ×
*n* locales. This was Stage 1 Q7 and is still unanswered. It is a direct, non-trivial cost on the
most important requirement I own, and it needs a number before Stage 3 plans content work.

**Q7 — Does an unmeasured N block v1?** My position: no. The escalation chain derives from the
user's cadence class `C`, not from N, and is fully shippable. But R-24 is then *unmet*, and the
release gate should record it as an open requirement rather than accepting a fabricated figure.
Confirm that framing.

**Q8 — Weekly digest.** UX proposed a weekly "41 exports, 2 failures, all healthy" notification
so the user learns the monitoring itself is alive. I want it — a silent monitoring system is
indistinguishable from a dead one — but it is a notification the user did not ask for. In or out
for v1?

**Q9 — Telemetry as a destination-list entry.** OBS-24 puts the OTLP endpoint in the destination
list as a first-class, revocable entry whose egress appears in history and in the ledger. That
interacts with R-32's allowlist UI and R-38's advisory entry, both owned by the security
engineer. Confirm the destination list is the single place all egress is enumerated.

### Conflicts with the parallel Stage 2 designs

**Q10 — The journal database's Data Protection class.** ADR-0005 puts the whole database at
`SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN`; I need
`CompleteUntilFirstUserAuthentication` for the state and journal tables, because a background
wake hours after lock must **open** the database cold and I do not believe `CompleteUnlessOpen`
permits that. If I am right, the journal is unwritable during exactly the wakes we most need to
record, including every locked-HealthKit failure. **This should be settled by a one-hour test on
a real locked device before M2, not by argument**, and the resolution is probably to split the
classes: payload blobs stay strong, the state database moves. Architect and security engineer
jointly.

**Q11 — One escalation threshold, three definitions.** UX derives it from a user-chosen cadence,
the reliability design from `clamp(2 · N_p95(class), 6 h, 48 h)`, the architecture design from
`lastSuccess + N`. R-23 is a Must and R-71 has not run, so a threshold that requires N cannot
ship on its own. My proposal is one function with two regimes (§Freshness target N) and a single
owner. **The PM should assign that owner in synthesis**, because three documents each holding a
version of the same constant is precisely how the twelve-state model ends up disagreeing with
itself in Stage 3.

**Q12 — Is `partial(deferred_discretionary)` healthy?** The reliability design says it is the
healthy steady state, not a warning, and I have mapped it to `Deferred` rather than `Partial`
accordingly. But it means a destination can sit in `partial` indefinitely while everything is
fine, and R-21's whole purpose is that `partial` is not `success`. I think the resolution is that
`partial(deferred_discretionary)` must still advance nothing on the freshness clock — so silence
still escalates, and the "healthy" reading cannot mask a stall. Confirm that reading, because if
it is wrong the two documents disagree about the product's most important state.

---

## ADRs I propose

| ID | Decision | Why it needs to be an ADR |
|---|---|---|
| **ADR-OBS-01** | The journal is the source of truth; OTLP is a deferred projection read from it. No spans are constructed during a run | It is the inversion of the owner's original OTel framing and the reason R-79 is met by construction. A future engineer will otherwise "improve" it into live instrumentation |
| **ADR-OBS-02** | The journal is tables in the architect's single SQLite store (ADR-0005), and a run's terminal record commits in the same `BEGIN IMMEDIATE` transaction as the anchor advance, the queue write and the ledger row | Records the coupling so nobody later moves the journal to its own database for convenience and silently breaks R-21's evidentiary basis |
| **ADR-OBS-03** | *Proposed, contingent on Q10's test.* The state and journal database is `CompleteUntilFirstUserAuthentication`, weaker than the payload blobs, justified by containing no health values and required to open during a locked-device background wake | A deliberate protection-class downgrade must be argued in writing, once, with the enforcing mechanism named — and this one currently contradicts ADR-0005 |
| **ADR-OBS-04** | Outcome is assigned per sink by one ordered decision procedure at seal, then aggregated to the run by the reliability design's severity order; interrupted sinks seal to `unknown_ack`, never `failed`; `success` requires confirming evidence and is enforced by a database constraint | This is the anti-false-success mechanism and the product's stated wedge |
| **ADR-OBS-05** | The widget reads an App Group snapshot file, not the database, and its timeline is a pre-computed escalation schedule | Both halves are non-obvious and both are load-bearing for R-23's degraded path |
| **ADR-OBS-06** | `os.Logger` only in app targets; no `swift-log` facade (R-50 requires an ADR) | A facade destroys `%{private}`, which is what makes the bundle's log section safe at all |
| **ADR-OBS-07** | No maintainer-bound telemetry, permanently (R-55 requires an ADR); accepted permanent fleet blindness (D-09) | The largest capability we are giving up. It should be a decision on the record, not a discovery |
| **ADR-OBS-08** | Emission is manifest-driven: the bundle and OTLP serialisers iterate the allowlist, never the record | Converts default-deny from a review practice into a structural property, which is the RK-5 mitigation |
| **ADR-OBS-09** | Freshness is published per freshness class as a conditioned p50/p95 pair, decomposed into `L_obs` and `L_del`, superseded by the device's own measured distribution once it qualifies; no unconditional N and no number at all before R-71 | The one number in the product most likely to be quietly turned into a promise. Seconds the reliability design's ADR-R9 rather than competing with it |
| **ADR-OBS-12** | One escalation-threshold function with a pre-spike and a post-spike regime, owned by one document | Three Stage 2 documents currently define it differently; without this the twelve-state model will disagree with itself |
| **ADR-OBS-10** | Metric dimensions use a coarsened projection of the span attribute vocabulary | Keeps the cardinality budget without losing span fidelity; will look like duplication to a future reader |
| **ADR-OBS-11** | The status record written to the user's own destination is the primary R-27 surface, ahead of OTLP | It is the only mechanism that detects a phone that is off, and it depends on nothing we might cut |

---

## Traceability

| PRD | Stage 1 | Section |
|---|---|---|
| R-20 | OBS-01, OBS-02 | The export journal |
| R-21 | OBS-04, OBS-11, SLO-3 | Outcome taxonomy |
| R-22 | OBS-13, SLO-4 | Failure attribution |
| R-23 | OBS-10, OBS-12, UX-22/33/35/36/37 | The escalation chain |
| R-24 | HK-32, AR-16, NFR-08 | Freshness target N |
| R-25 | UX-08/09/10 | Outcome taxonomy (acknowledgement unit), Verification |
| R-26 | OBS-05, OBS-06, OBS-07, OBS-08, OBS-09 | Redaction allowlist and the diagnostic bundle |
| R-27 | OBS-14, MKT-10 | The external monitoring signal |
| R-50 | OBS-29 | Signal taxonomy (log events), ADR-OBS-06 |
| R-51 | OBS-07, SEC-37/38/43 | Redaction allowlist |
| R-52 | OBS-22, SEC-35 | Verification |
| R-53 | OBS-15, OBS-19/20/21/23/25 | The OTLP projection |
| R-54 | OBS-16 | The OTLP projection |
| R-55 | OBS-27, SEC-36 | ADR-OBS-07, Verification |
| — | OBS-18 | Signal taxonomy and cardinality budget |
| — | OBS-24, OBS-31, OBS-32, OBS-33 | The OTLP projection, The export journal |
