# Reliability and Delivery Design — Stage 2

**Owner:** Reliability Engineer
**Stage:** 2 of 4 (System Design)
**Status:** Draft for PM synthesis and adversarial review
**Date:** 2026-09-03
**Toolchain:** Swift 6.3.3, minimum iOS 18.0 (D-05)

**Requirements owned:** R-03, R-09, R-11, R-21, R-22 (jointly with observability), R-24 (jointly
with observability), R-72 … R-79.
**Requirements this design is load-bearing for:** R-04, R-08, R-20, R-23, R-25, R-30, R-43,
R-44, R-83, R-86, R-88, R-91.
**Traces:** AR-03, AR-04, AR-06, AR-12, AR-13, AR-14, AR-16, AR-17, NFR-02, NFR-08, NFR-13,
NFR-15, NFR-16, NFR-18; AR-F-09, AR-F-10, AR-F-13.

---

## Executive summary

The product's pitch is a reliability claim made against a platform that offers no reliability
guarantees. iOS has no scheduling API (C-03), the HealthKit store is unreadable for the ten
minutes after lock and until the next unlock (C-02), background wakes are opportunistic and
capped, a force-quit stops everything until next launch (C-04), and all five sinks are systems
we do not control. **We cannot promise delivery. We can promise never to lie about it**, and
that is the property this document designs.

Eight invariants carry the whole design. Everything below is machinery for holding them.

| # | Invariant | Enforced by |
|---|---|---|
| **I1** | An anchor advances only in the same durable transaction that persists the batch it covers. | §Crash safety, transaction T1 (R-04, AR-03) |
| **I2** | Gaps are forbidden; duplicates are permitted. Where the design must choose, it chooses duplicates every time. | T1 ordering, one retained previous anchor generation |
| **I3** | A batch is released only on a *confirmed* acknowledgement from the sink. Unconfirmable transports never produce `success`. | §Delivery semantics (R-03, R-25) |
| **I4** | Eviction and its gap record commit atomically, or neither commits. | §Queue, transaction T3 (R-09) |
| **I5** | The union of gap intervals over-covers the measurement-time extent of every evicted sample. A gap record never under-states what was lost. | §Gap record, interval-set algebra |
| **I6** | Catch-up work (backfill, re-export, reconcile) is subordinate to live delivery and can never cause the eviction of live data. | §Admission control |
| **I7** | No background wake is spent on work whose outcome is already known to be failure. | §Circuit breaking |
| **I8** | Recovery decisions on the launch path are derivable from rows the launch path must read anyway. Repair is deferred. | §Recovery phases R0/R1/R2 (R-73) |

Three findings the PM needs before synthesis, stated here so they are not buried:

1. **R-21 taken literally makes the healthy common case `partial`, not `success`.** In a
   store-and-forward pipeline, reads and acknowledgements are decoupled across runs; a wake that
   reads 500 samples and hands them to a discretionary background transfer has acknowledged
   zero of them. This is correct and honest, but the taxonomy needs a cause code and the UI
   needs to stop treating `partial` as bad news. See §Delivery semantics and Open Question 1.
2. **R-21 has no member for "the platform refused us the read".** A locked device is the most
   common condition this app will ever encounter, and forcing it into `failed` makes the
   honesty story actively worse. I propose adding `blocked_device_locked`. Open Question 2.
3. **D-05's iOS 18.0 floor removes `BGContinuedProcessingTask`, which is what made R-11
   unattended.** On iOS 18–25 a full backfill needs foreground time or a long accumulation of
   opportunistic wakes. R-75's ≤30 min is achievable unattended only on iOS 26+. Open Question 5.

And one number: **R-73's 400 ms is achievable, with roughly 185 ms of margin on an iPhone 11**,
but only if the background launch path is treated as a closed list of permitted operations
rather than as "the app, started". §NFR design states the list and what it forbids.

---

## Delivery semantics per sink

### The pipeline and where durability sits

```
  HealthKit                                                     Sink
     │                                                            ▲
 (1) │ anchored / date-ranged query, paged                        │
     ▼                                                            │
 (2) value-type conversion at the @preconcurrency seam            │
     ▼                                                            │
 (3) canonicalise (units, time zone, UUID, observedAt, seq)       │
     ▼                                                            │
 (4) NDJSON → deflate → per-type blob segment, fsync              │
     ▼                                                            │
══(5) ══ T1: batch + segments + delivery rows + anchor ══ COMMIT ══  ◀── DURABILITY BOUNDARY
     ▼
 (6) per-sink framing (template, MQTT topic, file name) — derived, reconstructible
     ▼
 (7) transmit ──────────────────────────────────────────────────────▶
     ▼
══(8) ══ T2: delivery row → acked, refcount--, blob unlink if 0 ══ COMMIT ══ ◀── ACK BOUNDARY
```

Steps 1–4 are **volatile**: process death loses them and costs nothing, because the anchor has
not moved. Step 5 is the only write-ahead point in the system. Steps 6–7 are **idempotent and
replayable** by construction: the framing is a pure function of the committed batch, and R-84's
byte determinism is what makes replay safe rather than merely tolerable. Step 8 is the only
place our own crash can introduce a duplicate, and it does so deliberately (I2).

**Fan-out, not fan-read.** One anchor per type, one durable batch log, one *delivery cursor per
sink*. Five enabled sinks read HealthKit once, not five times. A batch carries a refcount equal
to the number of sinks that owed it delivery at enqueue time, and its bytes are released when
the refcount reaches zero. The alternative — a per-sink anchor set — multiplies HealthKit reads
by the sink count and blows R-72 and R-77 for no correctness benefit. This is ADR-R1.

Consequence to state plainly: a sink enabled after the fact has no history. Default is
"start from now", with an explicit backfill or window re-export offered at enable time, and the
egress ledger (R-30) records which it was.

### Acknowledgement boundaries

| Sink | Acknowledgement boundary | Confirmable | Idempotency mechanism | Principal failure modes | Outcome when unconfirmable |
|---|---|---|---|---|---|
| **Local file** | `write` + `fsync` of a temp file inside the destination directory, atomic `rename` to the final name, `fsync` of the directory — all inside a coordinated write against a resolved security-scoped bookmark | **Yes**, strongly. Local filesystem semantics. | Deterministic filename embedding `batchSequence` + idempotency key; atomic rename means replay overwrites byte-identically (R-84) | Stale/failed bookmark resolution; folder deleted or moved; `ENOSPC`; destination is an iCloud-backed folder and the file is dataless or upload-pending | n/a. **If the user pointed at an iCloud folder, our ack covers commit to the local filesystem only.** Upload is Apple's business, we ship no iCloud code (PC-3), and the UI says so. |
| **HTTPS (generic)** | Full request body sent **and** a response received whose status is in the destination's declared success range, **and** — if declared — its optional response assertion passes | **Yes** | `Idempotency-Key: <batchKey>` header, plus per-record `HKObject.uuid` for upsert (R-02) | 5xx, 429, timeouts, DNS, TLS trust change (halt per R-31), 4xx config/auth, body-size rejection, proxy 200-with-error-body | Body fully sent, response never read → `unknown_ack`. Batch stays queued and is retried. |
| **Home Assistant preset** | Identical to HTTPS: 2xx from `POST /api/states/<entity>` or the webhook | **Receipt yes, persistence no.** HA returns 200/201 on accepting a state set; it does **not** tell us the recorder or the long-term statistics engine accepted it. R-89's `state_class` failure is invisible in the response. | Entity ID + timestamp; a state set is last-write-wins per entity, idempotent by construction | Everything HTTPS has, plus: entity created but silently excluded from statistics; `unit_of_measurement` mismatch on re-point; token expiry | Ongoing runs report `success` on 2xx. **The statistics gap is closed at configuration time, not at delivery time**: R-25's mandatory test does a read-back of `unit_of_measurement`, `device_class`, `state_class` and state precision, and the destination cannot be saved if read-back fails. This is the one sink where the ack is weaker than it looks and the mitigation is a gate, not a retry. |
| **MQTT** | **QoS 0:** none. TCP write completion only. **QoS 1:** `PUBACK` for the packet identifier. **QoS 2:** `PUBCOMP`. | **QoS 0 no. QoS 1/2 yes.** | Topic path + per-record UUID; MQTT itself never dedupes, so convergence is the consumer's upsert. QoS 1 is at-least-once, which is exactly R-03. | Broker unreachable; CONNACK refused (bad credentials, client-ID clash); TLS trust for a self-signed broker; broker-side max packet size; session takeover by a duplicate client ID; retained-message quota | **QoS 0 is terminally `Sent, unconfirmed` (R-25) and never `success`, ever.** See the QoS 0 paradox below. |
| **Mac companion** | An application-level `ACK` frame carrying the batch idempotency key and `committedBytes`, emitted by the companion **after its own fsync + atomic rename** | **Yes**, and it is the strongest ack in the set because we defined it | Same batch key; the companion holds a persisted seen-key set and replies `ACK` (not `DUPLICATE-IGNORED`) to a replay, so a lost ack heals on retry | Peer not on the network; pairing revoked; companion disk full; connection dropped mid-transfer; version skew in the frame format | Transfer completed but connection dropped before the ACK frame → `unknown_ack`. Chunked transfer with committed offsets means a retry resumes rather than restarts. |

### The QoS 0 paradox, and how it resolves

If an unconfirmable delivery never releases its batch, a QoS-0 destination fills the 256 MB
queue and then evicts real health data forever. If it *does* release the batch, we have released
data we cannot prove arrived. Both are bad. The resolution:

- **QoS 0 releases the batch on write completion, and the delivery's terminal state is
  `sent_unconfirmed`, permanently, in the journal and the ledger.** It never becomes `success`,
  never contributes to "last successful export", and is never counted in `samplesAcknowledged`.
- Therefore a QoS-0-only configuration has **no** last-success clock, which would make R-23's
  watchdog fire forever. So a QoS-0 destination runs a separate, clearly-labelled
  "last unconfirmed send" clock, and the freshness escalation for that destination says
  *"we cannot confirm delivery to this destination — MQTT QoS 0 provides no acknowledgement"*
  rather than *"exports have stopped"*.
- **MQTT defaults to QoS 1.** QoS 0 is an explicit opt-in whose copy names the consequence in
  the same sentence as the toggle, and the choice is recorded in the ledger. ADR-R7.

Open Question 3 asks the PM to ratify the separate clock, because it is a visible product
behaviour and not purely an engineering choice.

### Delivery classes and what "at-least-once" costs each sink

R-03 is at-least-once with an idempotency key, and we do not claim exactly-once. What that means
per sink, concretely:

- **Local file** — a replay overwrites the same path with the same bytes. Duplicate cost: zero.
- **HTTPS / HA** — a replay re-POSTs. Duplicate cost: whatever the receiver's upsert-by-UUID
  costs it. The wire spec must state that receivers are required to be idempotent under
  upsert-by-UUID and *may* additionally short-circuit on `Idempotency-Key`; we do not require
  the latter.
- **MQTT QoS 1** — a replay republishes. The broker will deliver twice to subscribers. Duplicate
  cost: the consumer's upsert. The wire spec must say so, because MQTT users are the group most
  likely to be appending to a time series rather than upserting.
- **Mac companion** — the seen-key set absorbs it. Duplicate cost: one round trip.

### Partial acceptance

The batch is the unit of acknowledgement and acceptance is all-or-nothing. A receiver that
accepts some records and rejects others must return a non-success status; if it returns 2xx we
treat the whole batch as accepted, because we cannot parse arbitrary bodies (AR-21 forbids an
expression evaluator).

For receivers that signal partial acceptance in a 2xx body, the destination template may declare
one **response assertion** inside AR-21's closed grammar: a status range plus an optional
`(JSON pointer, expected literal)` equality check. If declared and unmet, the delivery is
`unknown_ack` and the batch is retried. This keeps the escape hatch inside the safe grammar and
does not introduce scripting.

### Run outcome derivation (R-21, joint with observability)

Per-sink terminal state for a run is computed first; the **run** outcome is the most severe
across sinks, under this severity order:

`success_nothing_due` < `success` < `partial` < `unknown_ack` < `abandoned_no_budget`
< `cancelled_by_system` < `failed`

Rationale for the two contentious placements: `failed` above `cancelled_by_system` because
"we ran and could not deliver" is more actionable to the user than "the OS stopped us";
`unknown_ack` above `partial` because ambiguity about delivered data is worse than certainty
about undelivered data.

Mechanising R-21's rule ("never `success` if acknowledged < read") requires scoping the counters
to the run's *own* batches:

```
run.samplesRead                     = samples read from HealthKit in this run
run.samplesEnqueued                 = samples durably committed in T1 in this run
run.samplesAckedFromThisRunsBatches = samples from this run's batches confirmed in T2 in this run
run.samplesAckedTotal               = all confirmations in this run, including older batches
```

- `success` requires `samplesAckedFromThisRunsBatches == samplesRead` and `samplesRead > 0`.
- `success_nothing_due` requires `samplesRead == 0` **and** the queue empty **and** the read
  actually succeeded. A locked-store read is not "nothing due".
- Everything else with `samplesEnqueued == samplesRead` but incomplete acks is `partial`, with a
  mandatory cause code: `deferred_discretionary`, `awaiting_unmetered`, `awaiting_wifi`,
  `budget_exhausted`, `breaker_open`, `types_purged`.

`partial(deferred_discretionary)` is the healthy steady state, not a warning. That is Open
Question 1.

---

## The bounded queue and drop policy

This is the one place the product deliberately loses health data. It is designed on the
assumption that the sentence "you lost my sleep data" will be quoted back at us, and every
choice below is made so that the answer is a precise date range, an exact count, a named cause
and a one-tap remedy — never "we're not sure".

### Storage layout

```
Application Support/<bundle>/state/          ← excluded from device backup (ADR-R4)
  reliability.sqlite                          WAL, one file, one schema version
  reliability.sqlite-wal                      checkpointed on foreground, capped 4 MB
  queue/
    staging/<batchSeq>/<typeId>.ndjson.gz     pre-commit; name derived from batch identity
    blobs/<batchSeq>/<typeId>.ndjson.gz       post-commit
    attempts/<deliveryId>.body                derived cache for background URLSession uploads
  checkpoints/<jobId>.json                    inspectable, versioned (R-86)
```

**SQLite for metadata, files for payload bytes.** Blobs live outside the database for three
reasons: 256 MB of blobs inside SQLite makes incremental deletion and WAL growth expensive and
turns launch into a WAL replay (which R-73 cannot afford); streaming a deflate output straight
into a file is how R-74's 100 MB ceiling is held; and file-per-(batch, type) is what makes
R-44's purge a `unlink` enumeration instead of a decompress-filter-recompress pass.

**Type-sharded segments exist because of R-44.** Revoking authorisation for a type must purge
that type's queued payloads within 60 seconds. If a batch were one blob containing all types,
purge would mean decompressing, filtering and recompressing up to 256 MB on an iPhone 11, which
is not a 60-second operation. Sharded by type it is a metadata update plus N unlinks. The cost
is file count: at ~600 KB per batch and 256 MB of cap that is ~400 batches, times up to ~60
types, so ~24,000 files worst case. Acceptable, and directory enumeration is never on the
R-73 path. ADR-R2.

Core tables (columns that matter, not a schema):

```
anchor(typeId PK, anchorToken, anchorTokenPrev, dateHighWaterMark,
       pendingRecoveryBatchSeq NULL, generation, updatedAt)

batch(seq PK, origin, createdAt, sampleTimeMin, sampleTimeMax, sampleCount,
      byteCount, refcount, evictionClass, state)
      -- origin ∈ {delta, backfill, reexport(gapId), reconcile}
      -- evictionClass ∈ {normal, pinned}
      -- state ∈ {live, evicted, lost}

batch_segment(batchSeq, typeId, path, byteCount, sampleCount)  PK(batchSeq, typeId)

delivery(id PK, batchSeq, sinkId, state, attempt, nextEarliestAt, lastErrorClass)
      -- state ∈ {pending, in_flight, acked, sent_unconfirmed, gapped, purged}

gap(id PK, sinkId, intervalStart, intervalEnd, sampleCount, batchSeqLow, batchSeqHigh,
    cause, status, createdAt, resolvedAt NULL, coalesceTolerance)
      -- cause ∈ {queue_eviction, blob_lost, purged_by_revocation}
      -- status ∈ {open, auto_resolving, reexport_queued, reexport_running, resolved, unresolvable}

queue_accounting(id=0, bytesOnDisk, batchCount, lastReconciledAt)
```

`queue_accounting.bytesOnDisk` is maintained in the same transaction as every blob insert and
delete, so occupancy is an O(1) read and never a directory walk. It is cross-checked against a
real disk walk in recovery phase R2 (never on the launch path), and a mismatch is a journalled
repair event rather than a silent correction.

### Watermarks and admission control

| Level | Bytes (256 MB cap) | Behaviour |
|---|---|---|
| Green | < 60% (154 MB) | Normal. All origins admitted. |
| Amber | ≥ 60% | **Catch-up admission stops.** New `backfill`, `reexport` and `reconcile` batches are refused; the owning job checkpoints and parks. `delta` still admitted. User-visible advisory. |
| Red | ≥ 80% (205 MB) | Amber, plus: derived `attempts/` caches purged, `PRAGMA wal_checkpoint(TRUNCATE)`, notification raised ("your destination has been unreachable long enough that data loss is approaching"). Still no eviction. |
| Over cap | ≥ 100% (256 MB) | Eviction (below). |

**Admission control is how I6 is held.** A one-tap re-export into a destination that is still
broken must not evict the live data it is trying to protect. Catch-up jobs are *paused* rather
than evicted, so the eviction policy itself stays exactly what D-11 says — strictly oldest-first
among admitted batches — and the thrash is designed out upstream instead of by adding a priority
exception to the drop policy. The user-visible cost is Open Question 8: a one-tap re-export can
legitimately sit in "will start when your destination recovers" for days.

### Eviction algorithm

Triggered inside the enqueue transaction, before commit, when `bytesOnDisk + newBatchBytes > cap`.

```
evict(newBatchBytes):
    target = cap * 0.90                       # low watermark, not "just enough"
    victims = []
    for b in batches where state = 'live'
                       order by seq asc:      # oldest-first (D-11); seq is monotonic,
                                              # per-installation, and clock-independent (AR-14)
        if bytesOnDisk - sum(victims.bytes) + newBatchBytes <= target: break
        if b.evictionClass = 'pinned': continue
        if any delivery(b) is 'in_flight' and handed to the system: continue
        victims.append(b)

    if bytesOnDisk - sum(victims.bytes) + newBatchBytes > cap:
        # everything left is in-flight or pinned
        abort enqueue; anchor NOT advanced
        outcome = failed(error_class: queue_admission_blocked)
        retry next wake                       # bounded: in-flight tasks complete or time out
        return

    T3 (single transaction):
        for b in victims:
            for d in deliveries(b) where state not in ('acked','sent_unconfirmed','purged'):
                merge_gap(d.sinkId, b)        # ← I5, see below
                d.state = 'gapped'
            b.state = 'evicted'
        adjust queue_accounting
        insert new batch rows + segments + deliveries + anchor advance
    COMMIT
    then unlink victim blobs                  # after commit, never before (see death point 12)
```

Four decisions worth defending:

- **Evict to a 90% low watermark, not to "just enough".** Evicting one batch per enqueue forever
  produces an eviction event, a gap merge and a notification on every single wake. Batching the
  pain into fewer, larger events is both cheaper and more legible.
- **Whole batches only.** A partially evicted batch cannot have an exact sample count or an exact
  date extent, and both are what the gap record promises.
- **Order by `seq`, not by date.** Sample dates are not monotonic across batches — a batch
  enqueued today can contain a three-week-old sleep session. `seq` is the only monotonic,
  clock-independent ordering available (AR-14), so "oldest-first" means *oldest observed*, and
  the UI copy must say "oldest data we were holding", not "oldest measurements".
- **The newest batch is always admitted** unless admission is physically blocked. The freshest
  data is the most valuable and the least likely to be recoverable by another route; the oldest
  is the most likely to be already superseded or re-readable from HealthKit.

The design does not claim eviction is reachable in practice. At the architect's REF-DELTA
(~20k samples/day, ~600 KB/day gzipped) a 256 MB cap absorbs over a year of continuous
destination downtime. The cap exists to bound worst-case disk, not to be hit. Raw-mode export of
a high-frequency store, or a stalled backfill, are the realistic paths to it.

### The gap record, and keeping it accurate across overlapping evictions

A gap record is **per sink**, because eviction only creates a gap for sinks that had not yet
acked. A naive single global gap record would tell a user their local-file export lost data when
only their broken HTTPS endpoint did.

Two representations are kept, because they answer different questions:

1. **A batch-sequence range** `[batchSeqLow, batchSeqHigh]`. Exact, and always a contiguous
   prefix range because eviction is strictly oldest-first. This is the audit artefact.
2. **A coalesced measurement-time interval set.** This is what the user sees and what re-export
   queries.

The interval set is where the care goes. Batch sample extents **overlap and are not ordered**,
so merging is genuine interval-set algebra, not appending to a range:

```
merge_gap(sinkId, batch):
    iv = [batch.sampleTimeMin, batch.sampleTimeMax)
    tol = current tolerance for this sink        # starts at 1 hour
    find all open gaps g for sinkId where g.interval overlaps or abuts iv within tol
    replace them with one gap:
        interval    = [min(starts), max(ends))
        sampleCount = sum(counts) + batch.sampleCount     # exact: batches hold disjoint samples
        batchSeqLow = min(lows), batchSeqHigh = max(highs)
        cause       = 'queue_eviction'
    if open gap count for sinkId > 512:
        tol = next(tol) in [1h, 6h, 24h, 7d]; re-coalesce
        # coarsen, never discard
```

The invariant this buys is **I5: over-cover, never under-cover.** Coalescing widens the interval
to include dates for which nothing was actually lost. That is deliberate and it is the honest
direction to be wrong in:

- Over-covering is *safe for re-export*, because re-reading data we already delivered is
  harmless under upsert-by-UUID (R-02).
- Over-covering is *honest in the UI*, provided the copy is right. The copy is therefore:
  *"At least 4,812 samples measured between 12 Aug 09:00 and 19 Aug 22:00 were dropped before
  they reached Grafana. Re-exporting this window re-reads everything in it."* The count is exact
  and labelled "at least" only because the interval may contain samples that were never queued
  at all; the interval is explicitly a superset.

Further gap-record rules:

- **Gap records are never evicted.** They are metadata, they are bounded by coalescing, and they
  are the product's only evidence of its own data loss. If a gap record cannot be persisted, the
  eviction does not commit (I4).
- **Eviction and gap record are one transaction.** T3 above. There is no interleaving in which
  bytes are gone and the record is not written.
- A gap whose interval falls entirely inside the R-08 reconciliation sweep window (default
  trailing 7 days) is created with status `auto_resolving`, because the next sweep will re-detect
  and re-deliver it without user action. It is still shown, still counted, and still logged — but
  the copy says "recovering automatically" instead of offering a button.
- Gaps are resolved by **coverage**, not by "the re-export finished". A completed re-export that
  covered 12–17 Aug against a gap of 12–19 Aug splits the gap into `resolved(12–17)` and
  `open(17–19)`. Resolved records stay in the ledger permanently (R-30 is append-only) and
  collapse in the UI.
- `cause = purged_by_revocation` (R-44) records a *deliberate* gap and offers **no** re-export,
  because we no longer have authorisation to read the type. `cause = blob_lost` records the
  unrecoverable branch of death point 7 and is the only cause we should ever have to apologise
  for.

### One-tap re-export, and how it interacts with anchors and the sweep

Re-export is **not** an anchor rewind. R-86 forbids anchors silently resetting, and rewinding an
opaque `HKQueryAnchor` to a date is not an operation the platform offers anyway. Re-export is a
date-ranged `HKSampleQuery` job:

```
reexport(gapId):
    plan  = { window: gap.interval (coalesced, so a superset),
              types:  types with data enabled at time of the re-export,
              sinks:  [gap.sinkId] only        ← other sinks already have this data
              chunk:  adaptive, newest-first,
              origin: reexport(gapId) }
    persist checkpoint (same format and machinery as backfill, §Resumable backfill)
    execute under admission control: enqueue the next chunk only while occupancy < Amber
    on chunk commit: update checkpoint
    on full coverage with confirmed acks: split/resolve the gap
```

Five interactions to be explicit about:

- **The live anchors are untouched.** Re-export uses date-ranged queries and its own checkpoint.
  It cannot cause a delta gap.
- **Re-export targets only the sink that lost data.** Fanning out to all sinks would send every
  other destination a large duplicate burst for no reason.
- **Re-export batches are `pinned` up to a sub-budget of 25% of the cap (64 MB)**, so an
  in-progress re-export is not the first thing evicted by the live traffic it is racing. Beyond
  the sub-budget it is paced by the sink's drain rate rather than pinned further.
- **Re-export is resumable and interruptible** with the same guarantees as backfill: at most one
  chunk re-done, never a skip.
- **The sweep and re-export must not duplicate each other's work.** A gap in `auto_resolving`
  cannot be manually re-exported; the button is replaced by "recovering automatically", and if
  the sweep fails to close it within two sweep intervals it transitions to `open` and the button
  returns.

### Purge on authorisation revocation (R-44)

60 seconds is the deadline and it is why the storage layout is type-sharded.

```
purge(typeId):                                # target: p99 < 10 s at full cap on REF-B
    T4: mark all delivery rows covering segments of typeId as 'purged'
        delete batch_segment rows for typeId
        adjust queue_accounting
        for each affected sink: merge_gap(sink, cause='purged_by_revocation')
        drop typeId's anchor row entirely     # re-authorisation starts from now, not from stale
    COMMIT
    unlink the segment files                  # enumerated, no rewrite
    purge attempts/ caches whose body may contain the type
```

The mark is inside the transaction so nothing of that type can be sent after the commit even if
the unlinks are still running; the unlinks then remove the bytes. Both must complete inside 60 s,
and the QA hook is a purge test with the queue deliberately at 256 MB (§Verification hooks).

---

## Retry, back-off and circuit breaking

### Error classification

Retry policy is a function of error *class*, never of error code. Classes, and their policy:

| Class | Examples | Retry | Breaker |
|---|---|---|---|
| `transient_network` | timeout, DNS failure, connection reset, no route | Yes, exponential + full jitter | Counts toward opening |
| `transient_server` | 5xx, 429, MQTT broker busy, companion busy | Yes; honour `Retry-After` (capped 24 h) | Counts toward opening |
| `awaiting_unmetered` | expensive/constrained network and the destination has not opted in | **Not a retry.** Wait for a suitable path via `NWPathMonitor` | **Does not count.** Not a destination failure. |
| `client_config` | 404, 400, 413, bad topic, unresolvable bookmark | One probe to rule out a transient, then stop | Opens immediately → `blocked_needs_user` |
| `auth` | 401, 403, MQTT CONNACK not-authorised, token expired | One probe, then stop | Opens immediately → `blocked_needs_user` |
| `pin_change_halt` | server certificate identity differs from the pinned one (R-31) | **Zero retries** | Halts the destination pending explicit re-approval |
| `local_storage_full` | `ENOSPC` writing a blob or the destination file | Not retried in this run | Does not open; escalates as a device condition |
| `store_locked` | `HKErrorDatabaseInaccessible` (C-02) | Not retried in this wake; return immediately | **Does not count.** Platform condition, not a failure. |
| `unknown_ack` | body sent, response lost | Yes, but 3 consecutive occurrences open the breaker | Counts, at a lower threshold |
| `protocol` | frame/version skew with the Mac companion, malformed broker response | One probe, then stop | Opens; likely needs a companion update |

The single most consequential line in this table is `client_config` / `auth`: **a broken token
gets one retry, not a schedule.** Retrying a 401 every fifteen minutes for a week is precisely
how a misconfiguration becomes a battery complaint, and the correct response is to stop and tell
the user, immediately.

### Back-off

```
delay(n) = random_uniform(0, min(cap, base · 2^n))          # full jitter
base = 15 s,  cap = 6 h,  n = consecutive failures for that sink
Retry-After, when present and parseable, overrides, capped at 24 h
```

Full jitter rather than decorrelated jitter: with a single client there is no thundering herd to
avoid, so jitter's job here is to stop retries locking in step with the OS's own wake cadence.
A deterministic back-off can land every retry inside the same unlucky wake slot indefinitely.

### Circuit breaker (per sink)

```
closed ──5 consecutive failures, or 3 consecutive unknown_ack──▶ open
closed ──any of client_config | auth | pin_change_halt | protocol──▶ open (immediately)
open   ──back-off elapsed, or app foregrounded──▶ half_open
half_open ──one real batch delivered and acked──▶ closed
half_open ──failure──▶ open (n incremented, back-off doubled)
open for ≥ 7 days ──▶ failing_persistently   (probe at most once per 6 h)
```

Three specifics:

- **The half-open probe is a real batch — the oldest pending one — not a synthetic canary.** A
  canary moves no data and can succeed where a real payload fails (size limits, schema
  rejection), which would close the breaker on a false signal.
- **While open, the sink does not request background wakes and is not attempted inside wakes
  requested by other sinks.** This is I7, and it is the mechanism by which a permanently broken
  destination costs approximately zero battery.
- **Foregrounding grants a free half-open probe**, ignoring back-off. The user is present, the
  device is unlocked, the screen is already lit, the energy is already being spent. This is the
  cheapest delivery opportunity the platform offers and the design leans on it hard: *the
  intended steady state is that most delivery happens while the user is holding the phone, and
  the background does as little as possible.*

Bounded, but never zero: `failing_persistently` still probes every 6 h, because destinations do
come back and a design that gives up permanently would need the user to notice and press a
button — which is the failure mode this product exists to eliminate.

### Interaction with the background wake budget (R-79, R-77)

A `BGAppRefreshTask` wake is ~30 s wall clock on the system's terms. The budget, on REF-B:

| Phase | Budget | Notes |
|---|---|---|
| Launch → first HealthKit query | **≤ 400 ms** | R-73. See §NFR design for the permitted-operations list. |
| Journal, ledger and telemetry writes, cumulative | **≤ 600 ms** | R-79 = 2% of 30 s. Achieved by keeping OTLP entirely off this path. |
| Read + transform + enqueue (T1) | ≤ 15 s at 10k samples | R-72 REF-B. The protected phase. |
| Delivery | **hard cap 12 s**, closed-breaker sinks only | At most **one** attempt per sink per wake. |
| Expiration reserve | **≥ 3 s** | Checkpoint, write the run terminus, `setTaskCompleted`. |

Four rules make retry compatible with a scarce wake budget:

1. **A wake never blocks the read/enqueue phase on delivery.** Enqueue first, deliver with what
   time is left. If no time is left the outcome is `partial(budget_exhausted)`, not `failed`, and
   I1 is untouched.
2. **At most one delivery attempt per sink per wake.** No retry loops inside a wake, ever. With a
   6 h back-off cap, a persistently failing destination costs a handful of TLS handshakes per day.
3. **Retries beyond the first use a background `URLSession` with `isDiscretionary = true`.** The
   first attempt is non-discretionary (freshness matters); retries are handed to the OS to
   schedule at its convenience, so their energy is not charged against our wake at all. This is
   the largest single lever in the whole battery budget. ADR-R5.
4. **MQTT and the Mac companion cannot use background `URLSession`** — they are not HTTP. They
   make progress only while our process runs, so their retry is naturally wake-gated. Caps:
   MQTT total ≤ 6 s per wake including connect, abandoned if CONNACK has not arrived in 3 s;
   the connection is held for the duration of a foreground session and **never across wakes**.

**R-77 budget (≤ 1% of a ~13 Wh battery per 24 h ≈ 90 CPU-seconds at the architect's ~1.5 W):**

| Consumer | Budget | Basis |
|---|---|---|
| Read + transform + enqueue at REF-DELTA (20k samples/day) | 60 CPU-s | 20,000 ÷ 1,600/s ≈ 13 s core, plus serialisation and gzip level 1 |
| Delivery, TLS handshakes, radio wake | 20 CPU-s | ~12 wakes/day with a closed breaker |
| Journal, ledger, accounting | 10 CPU-s | Piggy-backed on pipeline transactions |
| **A destination that is permanently broken** | **≈ 1.6 CPU-s** | 4 half-open probes/day × ~0.4 CPU-s. This is the number the breaker exists to produce. |

Named decisions that hold this: no timers and no polling of any kind (every wake is
observer-driven or system-scheduled); gzip level 1 (most of the ≥8:1 on NDJSON at a fraction of
the CPU — to be confirmed against the corpus); no MQTT keep-alive across wakes; OTLP flushed only
in the foreground; the breaker suppressing wake requests.

**RK-2 note.** If R-70 finds throughput is 400/s rather than 1,600/s, the read phase alone is
50 s for a day's REF-DELTA volume and does not fit one wake. The pipeline is therefore designed
so a wake processes a **bounded slice and checkpoints** — per-type, intra-run — precisely so that
an RK-2 miss changes the *number of wakes needed* and not the *correctness* of the design.
It will still invalidate the R-72 and R-75 numbers, which must then be re-baselined rather than
absorbed by relaxing the pipeline.

---

## Crash and interruption safety

### Transaction boundaries

Single SQLite database, WAL mode. `synchronous = FULL` for T1 (the write-ahead transaction, the
only one that must be atomic against power loss); `NORMAL` elsewhere. `wal_autocheckpoint`
tuned so the WAL stays under 4 MB, and a `TRUNCATE` checkpoint on every foreground entry —
because a large WAL turns process launch into a replay, and R-73 has no room for that.

**T1 — enqueue and anchor advance (the write-ahead transaction):**

```
1.  write each type's segment to queue/staging/<seq>/<typeId>.ndjson.gz
    fsync each file; fsync the staging directory
2.  BEGIN IMMEDIATE
      insert batch(seq, origin, sampleTimeMin/Max, sampleCount, byteCount,
                   refcount = |enabled sinks|, evictionClass, state='live')
      insert batch_segment rows (paths under blobs/, not staging/)
      insert delivery rows, one per enabled sink, state='pending'
      update anchor SET anchorTokenPrev = anchorToken,
                        anchorToken     = <new>,
                        dateHighWaterMark = max(old, batch.sampleTimeMax),
                        pendingRecoveryBatchSeq = seq,
                        generation = generation + 1
      update queue_accounting
      (if eviction was required) apply T3
3.  COMMIT
4.  rename staging/<seq> → blobs/<seq>
5.  update anchor SET pendingRecoveryBatchSeq = NULL     (cheap, unsynchronised)
6.  unlink evicted victims' blobs
```

Three windows exist and each is closed by a deterministic recovery action, not by a guess:

- **(1)…(3)** — orphan staging directory, no committed batch. Recovery unlinks it. Anchor
  unchanged, so the data is simply re-read. Zero loss.
- **(3)…(4)** — committed batch whose blobs are still in staging. **This is why the staging path
  is derived from the batch sequence**: recovery completes the rename deterministically rather
  than searching for a match. If staging is *also* gone, `pendingRecoveryBatchSeq` plus
  `anchorTokenPrev` let recovery roll the anchor back exactly one generation and delete the batch
  row — producing duplicates on re-read (permitted, I2) instead of a gap (forbidden).
- **(4)…(6)** — orphan blobs for evicted batches. Disk cost only; phase R2 unlinks them and
  corrects the accounting.

**Why one previous anchor generation, and only one.** Only the most recent T1 can be in the
post-commit/pre-rename state, so one generation of history is sufficient to make the only
otherwise-unrecoverable window recoverable. This closes the design's one real gap hole at the
cost of one extra column. The rollback is journalled as a `recovered_batch` event and is visible
in the run history, which is what R-86's "anchors never *silently* reset" actually asks for.
ADR-R3.

**Blobs are unlinked only after commit.** Reversing this — unlink then commit — creates a state
where a batch row exists, its bytes are gone, and it is not the newest batch, so no anchor
rollback is possible. That state has no recovery except a gap record. The ordering is the reason
death point 12 below is unreachable.

**Rejected alternative:** payload bytes as SQLite blobs inside T1. It closes all three windows
and is genuinely more elegant. Rejected because it breaks R-44's 60-second purge (no per-type
unlink), breaks R-74's streaming budget (no incremental deflate straight to a file), and inflates
the WAL against R-73. The trade is three narrow, deterministically-recoverable windows in
exchange for three NFRs.

**T2 — acknowledgement:** `delivery.state = acked`, `batch.refcount -= 1`, unlink segments and
delete rows when the refcount hits zero. One transaction, `synchronous = NORMAL`.

**T3 — eviction:** as given in §The bounded queue. Atomic with its gap records (I4).

**T4 — purge on revocation:** as given in §Purge.

### Every point the process can die

| # | Death point | State on disk | Recovery | Loss | Duplicates |
|---|---|---|---|---|---|
| 1 | The OS never woke us | Nothing | None needed. The **watchdog** records an expected-but-absent run; this is R-22 scheduling failure, not a run outcome. | none | none |
| 2 | During launch, before the `run_started` row | Nothing | Indistinguishable from #1. **Admitted blind spot** — see below. | none | none |
| 3 | Mid-HealthKit read, between pages | Nothing committed | Next run resumes from the unchanged anchor | none | none |
| 4 | In the query callback, before any blob is fsynced | Nothing committed | As #3 | none | none |
| 5 | After blob fsync, before `BEGIN` | Orphan `staging/<seq>` | R2 unlinks it; anchor unchanged → re-read | none | none |
| 6 | **Inside** `COMMIT` | WAL guarantees all-or-nothing | Either the anchor advanced with its batch, or neither did | none | none |
| 7 | After `COMMIT`, before the staging rename | Batch committed, blobs in staging | R1 completes the rename. If staging is gone: roll the anchor to `anchorTokenPrev`, delete the batch row, journal `recovered_batch` | none | ≤ 1 batch |
| 7b | As #7 **and** `anchorTokenPrev` unusable | Batch committed, blobs and prior anchor both gone | Mark batch `lost`, write `gap(cause=blob_lost)`, rely on R-08 sweep and the gap's re-export | ≤ 1 batch, **recorded** | none |
| 8 | After rename, before any delivery | Batch durable, deliveries `pending` | Nothing needed. The orphan `run_started` is closed as `cancelled_by_system` if an expiration marker exists, else `failed(process_death)` | none | none |
| 9 | Mid-transmit, body partially sent | Receiver has no complete request | Retry. The receiver never applied anything | none | none |
| 10 | Body fully sent, response lost | Delivery still `pending` | Retry. **`unknown_ack`** — the canonical at-least-once case | none | possible, by design |
| 11 | Ack received, T2 not yet committed | Delivery still `pending` | Redelivered once. **The only place our own crash creates a duplicate, and it is deliberate** (I2) | none | ≤ 1 batch |
| 12 | Mid-eviction, blobs unlinked before `COMMIT` | — | **Unreachable.** Unlink follows commit, by construction | — | — |
| 13 | Mid-eviction, after `COMMIT`, before unlink | Orphan blobs, no batch rows | R2 unlinks; accounting corrected | none | none |
| 14 | **Force-quit** (C-04) | Background transfers cancelled by the system; no relaunch | All `in_flight` deliveries revert to `pending` on next launch. The queue is reconstructible from our own state and **never** from `URLSession` state | none | possible, from #10/#11 |
| 15 | Device restore from backup | Reliability state absent by design (ADR-R4) | Anchors are *absent*, never *stale*. First launch offers "backfill" or "start from now" explicitly | none silent | — |
| 16 | Anchor invalidated by HealthKit re-sync | Anchor returns the entire store | Detected (below) → `resync` mode, journalled `anchor_invalidated`. Never a silent full re-export (R-86) | none | bounded by the sweep window |
| 17 | `ENOSPC` mid blob write | Staging partial | Discard staging; anchor unchanged; `failed(local_storage_full)`; escalate. **Never evict to make room for a read** — that trades unrecoverable queued data for data we can re-read | none | none |

**Death point 2 is an honesty problem, not a data problem, and it needs stating.** To attribute
"we ran but died instantly" we would have to write a journal row before the first HealthKit
query, which R-73's 400 ms cannot afford. So the `run_started` row is written *after* the query is
dispatched. A death in the ~200 ms before that is indistinguishable from never having been woken.
The correct product behaviour is therefore to report **"no record of a run"** rather than
**"iOS did not wake the app"** — R-22 asks us to attribute scheduling failure separately from
execution failure, and this design can do that for every case except a window of roughly 200 ms,
where the honest answer is that we do not know. Corroborating evidence is available
(`BGTaskScheduler` submission records, `UIApplication.backgroundRefreshStatus`, MetricKit's
aggregate background CPU) and should be shown, but must not be presented as proof.

**Anchor invalidation detection (#16):** a delta run for a type whose `dateHighWaterMark` is
recent must not return the whole store. Trip on either of: page volume > 20× the trailing median
for that type, or > 50,000 samples in a single delta run. On trip: do **not** enqueue the flood.
Enter `resync`: bound the query by `dateHighWaterMark − sweepWindow`, enqueue only that, and
journal `anchor_invalidated` with the new anchor recorded as a generation change. The thresholds
are tunable defaults and should be validated against the R-82 corpora.

### Recovery on launch, phased against R-73

Full recovery cannot sit on the 400 ms path. It is split so that the launch path reads only rows
it had to read anyway (I8):

| Phase | When | Budget | Work |
|---|---|---|---|
| **R0** | Before the first HealthKit query | **≤ 40 ms** | Open SQLite; compare `schemaVersion` as an integer; read the `anchor` row for each type in this wake's slice. The row already contains `anchorTokenPrev` and `pendingRecoveryBatchSeq`, so **the correct anchor to query with is computable from data already in hand** — zero extra I/O for recovery on the hot path. |
| **R1** | Concurrently with the first query | ≤ 300 ms | Complete staging renames for committed batches; apply anchor rollbacks flagged by `pendingRecoveryBatchSeq`; close orphan `run_started` rows; revert `in_flight` deliveries to `pending`. |
| **R2** | Foreground, or a `BGProcessingTask` | unbounded | Disk-walk accounting reconciliation; orphan blob unlink; gap-record coalescing; checkpoint validation; WAL truncate. Never on a background launch. |

**Schema migrations never run on a background launch.** If the on-disk `schemaVersion` differs
from the expected one, the wake journals `migration_pending` and returns immediately. Otherwise a
four-second migration inside a thirty-second wake, retried on every wake, is a permanent
outage that looks like a scheduling problem. ADR-R8.

---

## Resumable backfill and checkpoints

### Execution model, and the cost of D-05

R-11 wants years of history, resumable, without duplication or skip, streaming under R-74's
100 MB. R-78 forbids initiating it from a system-scheduled task. Two paths, because D-05 set the
floor at iOS 18.0 and `BGContinuedProcessingTask` is iOS 26+:

| OS | Mechanism | Unattended? |
|---|---|---|
| **iOS 26+** | `BGContinuedProcessingTask`, user-initiated, system progress UI, user-cancellable (AR-17) | **Yes.** R-75's ≤30 min p90 is achievable with the phone in a pocket. |
| **iOS 18–25** | Foreground-driven with progress UI and `isIdleTimerDisabled`; `beginBackgroundTask` gives ~30 s to checkpoint cleanly on backgrounding; thereafter it advances opportunistically inside `BGProcessingTask` wakes (idle-gated, killed the moment the user picks the device up) and resumes on next foreground | **No.** Either the user keeps the app open for the duration, or completion accumulates over days of opportunistic wakes. |

This is a real conflict with R-11 ("completes without babysitting") and R-75 (≤30 min p90 on
REF-B), and it is a direct consequence of D-05 rather than a design shortfall. Open Question 5
asks the PM to restate both per OS tier. The engine is identical across both paths; only the
host differs, so nothing here is thrown away if the floor later rises.

**Backfill never touches the live anchors.** It uses date-ranged `HKSampleQuery` with its own
`backfillHighWaterMark`, so an interrupted or abandoned backfill can never create a delta gap.
Using anchored queries for backfill would burn the live cursor. ADR-R10.

### Checkpoint format (R-86: inspectable and versioned)

One JSON file per job, written atomically (temp + fsync + rename), mirrored as a row in SQLite so
the two can be cross-validated. JSON specifically — not a binary plist, not `NSKeyedArchiver` —
because "inspectable" should mean a user or a maintainer can read it with `cat` and paste it into
an issue, and because it must round-trip through R-26's redacted diagnostic bundle. It contains
no sample values and no health data, only type identifiers and date ranges, which is what makes
it includable in that bundle at all.

```json
{
  "schemaVersion": 1,
  "jobId": "01J9F0K2QW8Z4YB7M3T5X6",
  "jobKind": "backfill",
  "createdAt": "2026-09-03T08:14:02Z",
  "updatedAt": "2026-09-03T08:41:55Z",
  "hostModel": "iPhone11,8",
  "plan": {
    "windowStart": "2019-01-01T00:00:00Z",
    "windowEnd":   "2026-09-03T00:00:00Z",
    "order": "newestFirst",
    "chunkTarget": { "samples": 5000, "uncompressedBytes": 4194304 },
    "mode": { "olderThanDays": 90, "old": "aggregate", "recent": "raw" },
    "types": ["HKQuantityTypeIdentifierStepCount", "HKCategoryTypeIdentifierSleepAnalysis"],
    "sinks": ["sink-7f3a"]
  },
  "progress": {
    "completed": [
      { "type": "HKQuantityTypeIdentifierStepCount",
        "ranges": [["2026-06-01T00:00:00Z", "2026-09-03T00:00:00Z"]] },
      { "type": "HKCategoryTypeIdentifierSleepAnalysis",
        "ranges": [["2026-08-01T00:00:00Z", "2026-09-03T00:00:00Z"]] }
    ],
    "cursor": { "typeIndex": 1, "chunkStart": "2026-07-25T00:00:00Z" },
    "samplesRead": 412393,
    "batchesEnqueued": 88,
    "lastBatchSequence": 10412,
    "pausedReason": "queue_amber"
  },
  "integrity": { "algorithm": "sha256", "value": "9f2c…" }
}
```

Design decisions in that structure:

- **`completed` is an explicit interval set per type, not a single cursor.** A single cursor
  cannot express "July and September are done, August was interrupted", which is exactly what
  happens with adaptive chunk sizes and per-type failures. Interval sets make resume idempotent
  and make "no skip" a checkable property rather than an assertion.
- **A chunk enters `completed` only after its batches are committed by T1.** So resume re-does at
  most one chunk: duplicates bounded by the chunk size, gaps zero. This is NFR-13 restated for
  backfill.
- **Newest-first.** If the user abandons at 40% they have the last three years, not the first
  three. It also interleaves sensibly with live delta traffic and makes the progress UI's
  remaining-time estimate honest sooner.
- **Adaptive chunk sizing**, target 5,000 samples or 4 MB uncompressed (NFR-16), starting at
  P1D and halving or doubling from the measured samples-per-chunk. This is how RK-2 is absorbed
  in the memory dimension: throughput changes the wall clock, not the ceiling.
- **`mode`** records the aggregate/raw split for old versus recent history. See R-75 in §NFR
  design; this is Open Question 6.
- **`pausedReason`** makes admission-control parking visible in the artefact, so "why is my
  backfill stuck" is answerable from the checkpoint alone.

### Resume, and corruption

```
resume(jobId):
    read checkpoint; verify integrity.value
    if unknown schemaVersion  → FAIL EXPLICITLY. Never migrate a version we do not know.
    if integrity mismatch     → FAIL EXPLICITLY.
        surface two named options: (a) discard and restart this job,
                                   (b) export the checkpoint for diagnosis (R-26)
        never a silent full re-export; never a silent skip (R-86)
    cross-check against SQLite mirror; disagreement is itself a corruption event
    reconstruct the remaining plan = plan.window minus union(progress.completed[type])
    resume at progress.cursor; the first chunk is re-done (bounded duplicates)
```

The point of failing explicitly rather than restarting is R-86's own reasoning: a silent full
re-export of five years into a metered HTTPS destination is a bill, and a silent skip is a gap
nobody knows about.

### Memory (R-74 ≤ 100 MB max, REF-B)

| Component | Budget |
|---|---|
| App baseline in a headless/`BGContinuedProcessingTask` host | ~40 MB |
| One query page (5,000 samples × ~400 B value types) | ~2 MB |
| Deflate window + output buffer | ~0.5 MB |
| SQLite page cache (pinned via `cache_size`, `mmap_size` bounded) | ≤ 8 MB |
| Framing/encode scratch | ≤ 2 MB |
| **Total** | **~53 MB, with ~47 MB of headroom** |

The decisions that produce O(1) memory in store size:

- Paging by a **moving predicate on the sort key**, never by `offset` — offset paging degrades and
  re-reads.
- Conversion to `Sendable` value types **at the query callback**, immediately, at the
  `@preconcurrency import HealthKit` seam. No `HKSample` object ever escapes into an actor.
- NDJSON encoded by a hand-rolled writer with a pre-resolved key order per type, straight into
  the deflate stream. Not `JSONEncoder` over dictionaries — which allocates per record, and whose
  key ordering R-84's byte determinism forbids us from relying on anyway.
- **Never** a `HKStatisticsCollectionQuery` over a five-year window at hourly granularity in one
  call; it materialises the whole collection. Chunked, same as raw.

---

## The freshness target

### What N actually is

R-24 wants a stated number. The rigorous version of that number is a **distribution conditioned
on device unlock**, and the design must not let it degrade into a promise. Two separable
quantities, because conflating them is how this becomes dishonest:

- **L_obs = `firstObservedAt − sample.endDate`.** How old the data was when we first saw it.
  This contains Apple Watch → iPhone sync latency, third-party apps backfilling weeks at once,
  and the user's lock/unlock behaviour. **We do not own any of it.**
- **L_del = `ackedAt − firstObservedAt`.** How long we took once the data was visible to us.
  **This is the only part we own**, and it is the only part the design is accountable for.

N as a product claim is a high quantile of `L_obs + L_del`, reported as the architect's NFR-08
shape — **p50 and p95 separately, measured only over intervals in which the device was unlocked
at least once, with no target while locked.** Both quantities are decomposed in the UI, because
"your watch took 90 minutes to sync and we delivered 40 seconds later" is a materially different
statement from "we sat on it for 90 minutes".

### Global, per-type, or something else

Neither. **Per freshness class**, assigned per type in the metric catalogue:

| Class | Character | Typical members | Shape of N |
|---|---|---|---|
| **A** | Phone-local, high-frequency, immediate background delivery available | steps, distance, flights climbed | minutes |
| **B** | Watch-synced; gated by Watch↔iPhone sync | heart rate, HRV, active energy, workouts | tens of minutes |
| **C** | Hourly-capped by the platform, or session-shaped and written long after the fact | sleep analysis, some third-party writers | **hours**, and stated in hours |
| **D** | Written by third-party apps or hardware on their own schedule | CGM glucose, scale weight, manual entries | **explicitly unpredictable**; we publish the measured distribution and make no claim |

Global is wrong because a single N is either useless (dominated by class D) or a lie (flattered by
class A). Per-type is wrong because ~200 numbers is unusable, most types have too little data on
any one device to estimate, and the platform's caps cluster into a handful of behaviours anyway.
**R-71's job is therefore to establish the class boundaries and the per-class distributions, not
200 individual numbers** — which also makes the spike substantially cheaper. ADR-R9.

### What the app claims before R-71 has run

**No number at all.** The pre-spike claim is a mechanism statement, not a figure:

- The UI shows the measured last-success age (R-23) and, per class, **the user's own device's
  observed distribution**: *"On this device, over the last 14 days, 90% of heart-rate samples
  reached Grafana within 2 h 10 m."*
- The README says N is not yet established and links to the R-71 findings document, which does
  not yet exist.

Once R-71 has run, the published per-class N becomes a **placeholder** used only until the local
estimate qualifies — the qualification bar being ≥ 14 days of observation and ≥ 100 samples in
that class. After that, the number shown is the user's own. This is strictly better than a
published constant: it is per-device, self-measured, and cannot be wrong about the device it is
describing. It does change what R-24 means, so it is Open Question 4.

### The watchdog threshold, derived

```
threshold(class) = clamp(2 · N_p95(class), floor = 6 h, cap = 48 h)
```

Escalation (R-23) fires against the **tightest class the user has data enabled for**. Two
user-facing staleness states, which is R-22's attribution extended to freshness:

- **`stale_platform_attributable`** — the device was off, locked or force-quit for the whole
  interval, or Background App Refresh is disabled. Copy names the cause. This still surfaces,
  because "we cannot tell you whether your data is flowing" is itself the news, but it does not
  accuse the destination or us.
- **`stale_ours_or_destination`** — we had opportunities and did not deliver. This is the alarm.

Conditioning matters and must survive into the UI: a user whose phone was off for three days has
not been failed by us, and telling them they have is how RK-4 becomes one-star reviews.

---

## NFR design

For each: the decisions that make it achievable, where the budget goes, and what would break it.
R-91 requires every NFR to map to a named test; §Verification hooks supplies the hooks.

### R-72 — Delta export of 10,000 samples: ≤ 8 s REF-A / ≤ 15 s REF-B, p90

**Decisions.** Value-type conversion at the callback with no intermediate collections. Single-pass
NDJSON encode with a pre-resolved per-type key order, written straight into the deflate stream.
One SQLite transaction per page, never per record. gzip level 1. No per-record `JSONEncoder`.

**Budget (REF-A, at the assumed 1,600 samples/s):** read 6.3 s + transform/encode 1.2 s +
compress 0.3 s + commit 0.2 s = **8.0 s. Zero headroom.**

**What breaks it.** RK-2. At 800 samples/s the read phase alone is 12.5 s and REF-A fails.
This NFR must be re-baselined from R-70's measurement, not relaxed by weakening the pipeline —
the pipeline has no fat in it.

### R-73 — Headless background launch to first HealthKit query: ≤ 400 ms, p90, REF-B

The tightest and most consequential NFR in the set. It is achievable, and the way it is achieved
is by treating the background launch path as a **closed list of permitted operations**.

**Permitted before the first HealthKit query, and nothing else:**
process start; one `HKHealthStore` instantiation; open SQLite; integer comparison of
`schemaVersion`; read the `anchor` rows for this wake's type slice (one indexed query);
construct and dispatch the query.

**Forbidden on that path:**

| Forbidden | Why |
|---|---|
| SwiftUI/UIKit scene or view-graph construction | A background launch has no UI and must not build one |
| Any DI container that instantiates the object graph eagerly | The architect's own documented failure mode: 8 s of graph construction is 27% of the wake |
| Destination adapter construction; the MQTT client; SwiftNIO | Must live in a target not touched by the background path |
| Decoding the metric catalogue from JSON | Compiled-in static table, or a memory-mapped lazily-indexed resource |
| Keychain access (`SecItemCopyMatching`) | Credentials are needed at *send* time, not read time, and Keychain access can block |
| Network stack init, `NWPathMonitor` start, TLS context creation | Needed at send time |
| Telemetry/OTLP init, log rotation | R-79's budget, and none of it is needed to read |
| The R-08 reconciliation sweep; accounting disk walk; gap coalescing | Recovery phase R2 |
| Any schema migration | ADR-R8: journal `migration_pending` and return |

**Budget (REF-B, cold, thermally unfavourable):**

| Step | ms |
|---|---|
| Process launch + dyld | ~120 |
| `HKHealthStore` init | ~30 |
| SQLite open + WAL recovery (WAL capped at 4 MB) | ~40 |
| Anchor row read | ~5 |
| Query construction + dispatch | ~20 |
| **Total** | **~215** |
| **Margin to 400 ms p90** | **~185** |

**The dependency budget is a launch-latency decision as much as a supply-chain one.** Zero
third-party dynamic frameworks on this path is what keeps dyld at ~120 ms; MQTT's SwiftNIO graph
must be linked into a target the background read path never touches.

**Enforcement.** A launch-path assertion in debug and test builds that traps if any forbidden
subsystem is initialised before the first query dispatch, plus signpost-based measurement in the
release gate.

### R-74 — Peak memory during full backfill: ≤ 100 MB, max, REF-B

See §Resumable backfill. Budgeted at ~53 MB with ~47 MB of headroom. The decisions are moving-
predicate paging, immediate value-type conversion, streaming deflate, pinned SQLite cache, and
never materialising a statistics collection.

### R-75 — Full backfill, 5 years of typical Watch history: ≤ 30 min, p90, REF-B, resumable

**Arithmetic.** Five years of typical Watch history is roughly 2.2 M samples (REF-STORE-XL is
4.3 M over ten years). At 1,600/s that is 23 min. At 800/s it is 46 min and the NFR fails.

**The lever that makes this comfortable rather than marginal** is the architect's fourth headline
finding: nobody ships millions of raw samples to Grafana. Aggregating five years to daily buckets
across ~40 curated families is ~73,000 records instead of 2.2 M — roughly 30× less work.

**Proposed default:** a full backfill offers **aggregates for history older than 90 days, raw for
the last 90 days**, with raw-everything available as an explicit choice that states its cost.
This reframes R-75 from "marginal at the assumed throughput and failing at half of it" to
"comfortable at either". It is a product decision, not mine — Open Question 6.

Also load-bearing: newest-first ordering (partial value delivered early) and the checkpoint
(interruption costs one chunk).

### R-76 — Cold start to interactive: ≤ 1,200 ms, p90, REF-B

Not primarily mine, but two constraints from this design bear on it: the same no-eager-graph
discipline serves both R-73 and R-76; and the run history, journal and queue UIs must be paged
queries, never a full-history load. A journal with 30 days of runs and a queue with 400 batches
must not be materialised to draw a status screen.

### R-77 — Steady-state battery: ≤ 1.0% per 24 h, mean, REF-A

Budget table given in §Retry (60 / 20 / 10 CPU-seconds, with a broken destination costing
≈ 1.6 CPU-s). The named decisions: no timers or polling of any kind; one delivery attempt per
sink per wake; discretionary background `URLSession` for retries; open breakers suppressing wake
requests; gzip level 1; no MQTT keep-alive across wakes; OTLP flushed only in the foreground.

**The number this NFR is really about** is the broken-destination case. A design that retried a
dead endpoint every fifteen minutes would spend more energy failing than succeeding, and the
circuit breaker plus the `client_config`/`auth` one-probe rule are what prevent that.

### R-78 — Full backfill battery: ≤ 12% per run, mean, REF-A; never from a system-scheduled task

**Decisions.** Backfill requires an interaction token that a `BGAppRefreshTask` cannot produce —
the prohibition is enforced structurally, not by convention. Aggregate-first defaults (R-75) cut
the work ~30×. Delivery of backfill batches is deferrable to Wi-Fi and, optionally, to charging.
The progress UI states an estimated battery cost **before** the user starts.

**Budget.** 23 min of sustained work at ~1.5 W against ~13 Wh ≈ 8–10%, inside the ceiling with
little room. Aggregate-first brings a typical full backfill to ≈ 1–2%, which is what makes the
ceiling comfortable.

### R-79 — Wake budget consumed by telemetry: ≤ 2%, p90, REF-B

2% of ~30 s is **600 ms**, and that is the whole budget for the journal (R-20), the ledger (R-30)
and any OTLP (R-53).

**The one decision that makes this achievable: OTLP export never runs inside a background wake.**
An OTLP/HTTP export means DNS, a TLS handshake and a POST — comfortably 100% of a 600 ms budget on
its own. Spans are written to a durable bounded buffer during the wake and flushed on foreground.
ADR-R6.

The rest: per-phase timings captured with `ContinuousClock` into a stack-allocated struct and
written **once** at run end; journal rows piggy-backed on pipeline transactions wherever the
schema allows, so their marginal I/O is zero; `os_signpost` only in instrumented builds; and
`os.Logger` calls on the background path drawn from a fixed set with no interpolation of
collections (which is also what keeps R-51's allowlist tractable).

**Budget:** `run_started` 8 ms + per-phase marks ~0 (in-memory) + run terminus and counters
25 ms + ledger append 15 ms = **~50 ms of 600 ms**. The headroom exists entirely because the
expensive thing was moved off the path rather than optimised.

### RK-2, stated once for all of the above

R-72, R-75 and the R-77 read allocation all rest on ~1,600 samples/s, which is unvalidated
pending R-70. The design absorbs a miss structurally — bounded slices with intra-run checkpoints
mean a slower store needs *more wakes*, not a different architecture — but the **numbers** in
this section must be re-baselined from R-70 rather than quietly relaxed. Open Question 9.

---

## Degradation ladder

| # | Condition | Behaviour | User-visible consequence | R-21 outcome |
|---|---|---|---|---|
| 1 | Destination down (5xx / timeout) | Exponential back-off with full jitter; breaker opens after 5 failures; queue grows | "Retrying. Last confirmed delivery 3 h ago." Then the R-23 escalation once the breaker opens | `partial(breaker_open)` per run; `failed(transient_server)` on the attempt that opens the breaker |
| 2 | Destination misconfigured (404/400/413) | One probe, then `blocked_needs_user`. **No scheduled retry.** | Notification + in-app banner naming the destination and the fix | `failed(client_config)` |
| 3 | Credential rejected (401/403) | As #2 | "Grafana rejected your token." Direct link to re-enter it | `failed(auth)` |
| 4 | TLS pin change (R-31) | **Halt.** Zero retries. Queue preserved intact. | Explicit re-approval screen showing both certificate identities | `failed(pin_change_halt)` |
| 5 | **Device locked > 10 min (C-02)** | Read fails with `HKErrorDatabaseInaccessible`; return immediately, no retry in-wake. **Still attempt delivery of already-queued batches** — a locked device blocks reads, not sends. Breaker untouched. | Nothing alarming. Status reads "waiting for you to unlock", and the freshness state is `stale_platform_attributable` | **Taxonomy gap.** Proposed `blocked_device_locked`; fallback `cancelled_by_system(store_locked)`. Open Question 2 |
| 6 | Low Power Mode | Backfill and re-export suspended; delta reads and delivery continue; all retries become discretionary; back-offs ×4; no MQTT reconnect except in the foreground | "Low Power Mode: exports continue, catch-up paused" | Runs as normal; the parked job records `abandoned_no_budget(low_power_mode)` |
| 7 | Thermal state ≥ `.serious` | Backfill suspended; batch sizes halved; compression dropped to level 0 | "Paused while your iPhone cools down" | `abandoned_no_budget(thermal)` |
| 8 | Background App Refresh disabled | `BGTaskScheduler` submissions fail; observer background delivery degrades (R-71 must measure by how much). Fall back entirely to foreground and Shortcuts (R-68). The local-notification watchdog still works — it does not need background execution | "Automatic export is off because Background App Refresh is disabled", with a Settings deep link. Disclosed pre-permission by R-63 | No run at all → **R-22 scheduling attribution**, surfaced by the watchdog, not a run outcome |
| 9 | Queue ≥ 60% (Amber) | Catch-up admission stops; catch-up jobs checkpoint and park | Advisory in the destination's row | `partial` for the paused job's next tick; live runs unaffected |
| 10 | Queue ≥ 80% (Red) | Amber, plus derived caches purged and the WAL truncated; notification raised | "Your destination has been unreachable long enough that data loss is approaching" | as #1 |
| 11 | **Queue full (100%)** | Oldest-first eviction to a 90% low watermark; per-sink gap records committed atomically | "At least N samples measured between A and B were dropped before they reached <sink>." One-tap re-export. **Proposed: a notification fires unconditionally** | **A separate ledger event with its own escalation, not a run outcome.** The run itself may legitimately be `success`. Data loss must not be hidden inside a run's status. Open Question 7 |
| 12 | Device storage full (`ENOSPC`) | Stop enqueueing. **Do not evict** — eviction would not help if the *device* is full and would lose data for nothing | Hard escalation; this one is user-fixable | `failed(local_storage_full)` |
| 13 | Network metered or constrained, destination not opted in | Wait on `NWPathMonitor`. **The breaker does not open** — this is not a destination failure | "Waiting for Wi-Fi (18 MB queued)" — explicitly *not* "broken" | `partial(awaiting_unmetered)` |
| 14 | Force-quit (C-04) | Nothing runs. Transfers cancelled by the system; no relaunch. `in_flight` reverts to `pending` at next launch | Widget and watchdog surface the staleness. **Copy must name force-quit as a cause**, because users do it deliberately and then blame us (RK-4) | No run → R-22 scheduling attribution |
| 15 | HealthKit authorisation revoked for a type | Purge within 60 s (R-44); `gap(cause=purged_by_revocation)`; **no re-export offered**; that type's anchor dropped | "Sleep is no longer being exported because you revoked access." | `partial(types_purged)`, or `success` if no purged type was in scope for the run |
| 16 | Mac companion not on the network | Breaker opens after 5 attempts; **no wakes requested** while open; free probe on every foreground | "Your Mac hasn't been reachable since Tuesday." | `partial(breaker_open)` → `failed(transient_network)` |
| 17 | MQTT QoS 0 configured | Every delivery is terminally `sent_unconfirmed`; the destination runs a separate "last unconfirmed send" clock | "Sent, unconfirmed — MQTT QoS 0 cannot confirm delivery" (R-25) | Never `success`. `unknown_ack` on the run when QoS 0 is the only sink |
| 18 | Two devices exporting to one sink (AR-15) | Raw mode is safe under upsert-by-UUID; **aggregate mode is not**. Non-designated devices are manual-export-only | "This iPad is set to manual export; your iPhone is the designated exporter for Grafana" | as normal for the designated device |

---

## Verification hooks

What the QA lead needs from this design.

**Fault-injection seams (R-83 asks for six named seams in test builds only). I need these:**

| Seam | Purpose |
|---|---|
| `KillAt(point)` | Deterministically terminate at each of the 17 enumerated death points |
| `AckOracle(script)` | Produce lost-ack, duplicate-ack, late-ack and partial-acceptance responses per sink |
| `QueuePressure(bytes)` | Force the queue to any occupancy so eviction is deterministic rather than incidental |
| `StoreLocked` | Simulate `HKErrorDatabaseInaccessible` on demand |
| `WakeBudget(ms)` | Shorten the wake so expiration handlers and checkpoints are exercised every run |
| `SinkBehaviour(script)` | Per-sink latency, error class and breaker-state scripting |
| `ClockSkew(delta)` | Device clock moved backwards; asserts no timestamp is load-bearing (AR-14) |

That is seven. R-83 names six; the PM should either raise the count or let QA fold `ClockSkew`
into an existing seam.

**Property tests (over arbitrary interleavings of enqueue, evict, ack, purge and crash):**

- `delivered(sink) ∪ gapCovered(sink) ⊇ read` — no silent loss, for every sink. **This is the
  single most important test in the product.**
- `⋃ gapIntervals(sink) ⊇ measurementExtent(evictedSamples(sink))` — I5, gap records never
  under-cover.
- `outcome ≠ success` whenever `samplesAckedFromThisRunsBatches < samplesRead` — R-21, mechanised.
- Anchors are monotonic per type except across a journalled `recovered_batch` or
  `anchor_invalidated` event — R-86.

**Named tests, mapped to requirements:**

| Test | Requirement |
|---|---|
| Launch-path assertion: trap on any forbidden subsystem initialised before the first query | R-73 |
| Signpost measurement of launch → first query, p90 over ≥ 100 cold background launches on REF-B | R-73, R-91 |
| Fill-the-queue with a seeded corpus and fixed batch sizes; assert the gap record byte-for-byte against a golden file (R-84's determinism makes this possible) | R-09 |
| Overlapping-eviction gap test: batches with deliberately interleaved sample extents; assert the coalesced interval set over-covers and the count is exact | R-09, I5 |
| Re-export against a still-broken destination; assert admission control parks it and no live batch is evicted | R-09, I6 |
| R-44 purge test **with the queue at 256 MB**; assert < 60 s and that nothing of the purged type is sent afterwards | R-44 |
| Checkpoint golden files; corruption test (bad checksum, unknown version) asserting explicit failure and no full re-export | R-86 |
| Kill-and-resume backfill at every chunk boundary; assert zero skip and ≤ one chunk duplicated | R-11, NFR-13 |
| MQTT QoS 0 test asserting the outcome is **never** `success` and the separate clock is used | R-25 |
| HA read-back test of `unit_of_measurement`, `device_class`, `state_class`, precision, at two pinned versions | R-89 |
| Force-quit mid-transfer; assert the queue reconstructs from our state and not from `URLSession` state | C-04, AR-12 |
| Restore-from-backup test; assert anchors are absent rather than stale and the user is offered an explicit choice | ADR-R4 |
| Anchor-invalidation test: corrupt/reset an anchor, assert `resync` mode and a journalled event, not a flood | R-86, #16 |

**R-88 soak protocol additions (≥ 21 days).** Record every eviction, every `unknown_ack`, every
`anchor_invalidated`, every `recovered_batch` and every `blocked_device_locked`; the end-of-soak
reconciliation must **account for each one individually**, not merely net to zero. Measure the
duplicate rate against NFR-18's ≤ 0.1% as well as the zero-loss assertion — a design that
achieves zero loss by duplicating everything is passing the wrong test.

---

## Open questions for the PM

1. **R-21 makes the healthy case `partial`.** In a store-and-forward pipeline, a wake that reads
   and durably enqueues 500 samples and hands them to a discretionary transfer has acknowledged
   none of them, so R-21 forbids `success`. That is correct and honest, but it means most runs are
   `partial`. Do you accept `partial` carrying a mandatory cause code, with
   `partial(deferred_discretionary)` presented as "Queued, awaiting delivery" rather than as a
   problem? Joint with observability. *My recommendation: yes; the user-facing headline should be
   the freshness clock, and the run outcome list should be the audit trail.*
2. **R-21's taxonomy has no member for "the platform refused us the read".** A locked device
   (C-02) is the most common condition this app will encounter. Forcing it into `failed` makes the
   UI say "failed" for the least alarming thing that happens. *My recommendation: add
   `blocked_device_locked`.* Fallback if the taxonomy is frozen:
   `cancelled_by_system(error_class: store_locked)`, excluded from the breaker and from the
   escalation's "our fault" state.
3. **MQTT QoS 0.** Ratify: QoS 1 default; QoS 0 opt-in with the consequence named in the same
   sentence as the toggle; QoS 0 deliveries terminally `sent_unconfirmed`; and a QoS-0-only
   destination gets a separate, differently-labelled "last unconfirmed send" clock instead of
   contributing to "last successful export" for R-23 and R-27.
4. **R-24's N.** Accept that N is (a) per freshness class A–D rather than global or per-type, and
   (b) **the user's own device's measured p95** once ≥ 14 days and ≥ 100 samples in that class
   are available, with R-71's published figure used only as a placeholder before then? This is a
   better claim than a published constant, but it changes what "a stated number" means in R-24.
5. **D-05 versus R-11 and R-75.** `BGContinuedProcessingTask` is iOS 26+. On iOS 18–25 an
   unattended full backfill does not exist: it needs foreground time or many opportunistic
   `BGProcessingTask` wakes. Do we restate R-11's "without babysitting" and R-75's ≤ 30 min per OS
   tier, or raise the floor for the backfill feature only? *My recommendation: restate per tier
   and say so in the App Store description; do not raise the floor, RK-8 is worse.*
6. **Backfill defaults to aggregates for history older than 90 days**, raw within 90 days, with
   raw-everything available explicitly. It is a ~30× cost reduction that makes R-75 and R-78
   comfortable instead of marginal, and it matches what users actually configure — but it means
   the default "export my whole history" is not sample-level for old data, and somebody will
   notice.
7. **Should an eviction fire a local notification unconditionally**, the way R-40 does for a
   destination change? It is the one place we deliberately lose health data, and a silent gap
   record sitting in a list contradicts "loud when it stops". *My recommendation: yes, and it
   should not be suppressible separately from R-40's.*
8. **Re-export is subordinate to live delivery** (I6), so a one-tap re-export into a destination
   that is still down will sit parked. Is *"Queued — will start when Grafana is reachable"*
   acceptable copy for something the PRD calls one-tap? The alternative is letting a re-export
   evict live data, which I will not design.
9. **May I have R-70's result before §NFR design is frozen?** R-72 has zero headroom at the
   assumed 1,600 samples/s and R-75 fails outright at half of it. I would rather re-baseline from
   a measurement than ship budgets that RK-2 voids. This is the cheapest risk reduction available
   and §7.1 already sequences it first.
10. **Confirm the backup split** (ADR-R4): configuration backed up with credentials redacted; all
    anchors, queue, journal and checkpoints excluded. It guarantees no silent post-restore gap,
    at the cost of a restored phone asking the user to reconfigure and then choose
    backfill-or-start-from-now.

---

## ADRs I propose

| ID | Decision | Consequence if reversed |
|---|---|---|
| **ADR-R1** | One anchor per type, one shared durable batch log, one delivery cursor per sink. Not per-sink anchors. | Per-sink anchors multiply HealthKit reads by the sink count and void R-72 and R-77 for no correctness gain. |
| **ADR-R2** | SQLite (WAL) for metadata; payload bytes in files **sharded per (batch, type)**, outside the database. | Blobs in SQLite make R-44's 60 s purge impossible on REF-B, break R-74's streaming, and inflate the WAL against R-73. |
| **ADR-R3** | Retain exactly one previous anchor generation per type, enabling a journalled single-transaction rollback. | Without it, the post-commit/pre-rename window can only be closed with a gap record — i.e. real data loss where duplicates would have sufficed (I2). |
| **ADR-R4** | All reliability state (anchors, queue, journal payloads, checkpoints) is excluded from device backup. Configuration is backed up with credentials redacted. | Backing up anchors but not the queue produces stale anchors over an empty queue: a silent gap, which is the single worst failure available to this product. |
| **ADR-R5** | First delivery attempt non-discretionary; all retries use a discretionary background `URLSession`. At most one attempt per sink per wake. Open breakers do not request wakes. | This is the mechanism that keeps a broken destination near-free (R-77) and retry compatible with a ~30 s wake. |
| **ADR-R6** | OTLP export never runs inside a background wake. Spans go to a durable bounded buffer and flush on foreground. | An OTLP HTTP export is DNS + TLS + POST — 100% of R-79's 600 ms budget on its own. |
| **ADR-R7** | MQTT defaults to QoS 1. QoS 0 is opt-in, terminally `sent_unconfirmed`, and never `success`. | QoS 0 as a default silently converts "delivered" into "written to a socket", which is exactly the lie the product exists not to tell (R-25). |
| **ADR-R8** | No schema migration on a background launch path. Journal `migration_pending` and return. | A multi-second migration retried inside every ~30 s wake is a permanent outage that presents as a scheduling problem. |
| **ADR-R9** | Freshness is expressed per class (A–D), not globally and not per type; R-71 measures class boundaries and per-class distributions. | A global N is either useless or flattering; 200 per-type numbers are unmeasurable on one device and unusable in a UI. |
| **ADR-R10** | Backfill and re-export use date-ranged queries and their own high-water marks. They never read or advance the live anchors. | Sharing anchors lets an abandoned backfill create a delta gap — the failure mode R-04 exists to prevent. |
| **ADR-R11** | Catch-up work is subordinate to live delivery via admission control at 60% occupancy; the eviction policy itself stays strictly oldest-first per D-11. | Without admission control, a one-tap re-export into a broken destination evicts the live data it was invoked to protect. |

---

## Traceability

| PRD requirement | Where designed |
|---|---|
| R-03 at-least-once + idempotency key | §Delivery semantics (per-sink table, delivery classes, partial acceptance) |
| R-04 write-ahead anchors | §Crash safety (T1, ADR-R3, death points 5–7b) |
| R-08 reconciliation interaction | §Gap record (`auto_resolving`), §Crash safety #16 |
| R-09 bounded queue, eviction, gap record, re-export | §The bounded queue and drop policy (whole section) |
| R-11 resumable backfill | §Resumable backfill and checkpoints |
| R-21 outcome taxonomy | §Run outcome derivation; §Degradation ladder; Open Questions 1–2 |
| R-22 scheduling vs execution attribution | §Crash safety (death points 1, 2, 14); §Degradation ladder rows 8, 14 |
| R-24 freshness target | §The freshness target; ADR-R9; Open Question 4 |
| R-25 `Sent, unconfirmed` | §The QoS 0 paradox; ADR-R7; ladder row 17 |
| R-43 delete-all / R-44 purge | §Purge on authorisation revocation; ADR-R2 |
| R-72 … R-79 | §NFR design (one subsection each, with budgets) |
| R-83 fault-injection seams | §Verification hooks |
| R-86 inspectable versioned checkpoint | §Checkpoint format; §Resume and corruption |
| R-88 soak protocol | §Verification hooks (soak additions) |
| R-91 NFR→test mapping | §Verification hooks (named test table) |
