# Observability Engineer — Stage 1 Contribution

> Stage 1 output: requirements with acceptance criteria. No Swift, no collector configuration.
> Requirement IDs use the `OBS-` prefix. Priorities use MoSCoW.
> Research current as of **2 September 2026**. Claims that came from my own judgement rather
> than a citable source are labelled **[assumption]**.

---

## Executive summary

The owner asked for OpenTelemetry tracing plus "whatever logging framework is most popular".
Both halves of that direction survive contact with the problem, but not in the shape the
words imply.

**On OpenTelemetry.** It is genuinely viable on Apple platforms in 2026, and more viable than
I expected before checking. `opentelemetry-swift-core` is a real, actively maintained,
Apache-2.0 API+SDK package that builds for iOS 12+, macOS 10.13+, watchOS 4+, tvOS 12+ and
visionOS 1+, with *zero* transitive dependencies on Apple platforms [1][2]. Tracing and
Baggage are stable [3][4]. Commercial mobile vendors — Embrace, Elastic, Datadog, AWS — ship
it in production iOS SDKs [5][6][7]. This is not a server-side story with a bolted-on mobile
client. But it is a *thin* story: three maintainers [8], metrics implemented against an
outdated spec and expected to change, logs at beta quality [3][4], and mobile
auto-instrumentation still openly tracked as behind `opentelemetry-android` [9]. The OTLP
exporters also live in the heavier sibling package and drag in SwiftProtobuf (HTTP) or
grpc-swift plus SwiftNIO (gRPC) [10][11][12].

The honest recommendation is therefore: **adopt OpenTelemetry as our data model and wire
format, not as the app's observability substrate.** Instrument with the OTel API, keep the
span/metric/attribute vocabulary OTel-conformant, and offer OTLP/HTTP export to a
user-supplied collector — but make the *source of truth* an app-owned durable diagnostic
journal that we control, because OTel cannot solve the problem the owner actually described.

**On the problem the owner actually described.** "Why did an export fail on someone's phone
three days ago" is not answerable by OTel and not answerable by `os_log` either, for one
concrete platform reason: on iOS, `OSLogStore` can only be opened with
`.currentProcessIdentifier` scope, and cannot read entries written by a *previous run* of our
own app [13][14][15]. A background wake that failed three days ago is in a process that no
longer exists. Its logs are unreachable. Apple has an open enhancement request for this
(r. 57880434) and it has not shipped [15]. Any answer to the owner's question therefore
requires the app to own a durable, on-disk, structured record of every export run. That
record is the product feature. OTLP is a projection of it.

**On logging.** "Most popular" resolves differently than the phrasing suggests. On Apple
platforms the answer is Apple's unified logging (`os.Logger`), and Apple's own `swift-log`
README explicitly warns against routing `os_log` through `swift-log`, because the available
backend forces `%{public}@`, eagerly interpolates, loses performance, and — decisively for us
— **destroys the `%{private}` privacy annotations** [16][17][18]. Those annotations are the
single best redaction primitive available to us in a health app: dynamic strings are redacted
by default unless we opt them into `%{public}`. Throwing that away to gain a facade we do not
need would be actively harmful. Recommendation: `os.Logger` only in app targets, no
`swift-log` facade in v1, and a separate schema-constrained journal for the durable signal.

**On priority.** I believe the in-app export history and the redacted diagnostic bundle
outrank OTel in v1, and I am willing to be held to that. The incumbent's entire published
troubleshooting workflow is built on exactly these two things — "Activity Logs" and an "App
Event Logs diagnostic ZIP" [19][20] — and its most damaging documented bug is a run that
reports **"Succeeded"** while nothing arrives at the user's Home Assistant [21]. No OTLP
endpoint catches that. A history screen that distinguishes *sent* from *acknowledged* does.

**On the central tension.** Resolved by making the default posture zero-egress and by
constraining telemetry content with an *allowlist*, not a denylist. Three specific attributes
that OTel HTTP semantic conventions would normally require us to set — `server.address`,
`url.full`, `server.port` — are the exact fields that reveal where someone gets treated. We
must deliberately omit them, which means we **must not use the stock `URLSessionInstrumentation`**,
because its job is to populate them. I recommend the project accept a documented,
intentional deviation from stable HTTP semconv on privacy grounds.

---

## Ecosystem assessment: OpenTelemetry on Apple platforms

### Straight verdict

**Viable, with a narrow shape. Use `opentelemetry-swift-core` for the API and SDK, OTLP/HTTP
only for export, and do not rely on OTel for on-device durability or for the metrics/logs
data model in v1.**

### The three things the owner may have conflated

There are three distinct efforts with similar names. Only one is relevant to a mobile app.

| Project | What it actually is | Relevant to us? |
|---|---|---|
| `open-telemetry/opentelemetry-swift` | The official OTel Swift SDK plus instrumentations and exporters. Latest **2.5.1** (Aug 2026) [22]. Apache-2.0 [11]. | **Yes** — but only the exporter targets. |
| `open-telemetry/opentelemetry-swift-core` | API + SDK + Stdout exporter, split out of the above to remove dependency weight. Latest **2.5.1** (29 Aug 2026) [2][23]. | **Yes — this is the dependency we want.** |
| `swift-otel/swift-otel` | An OTLP *backend* for `swift-log` / `swift-metrics` / `swift-distributed-tracing`. 1.0.0 Sept 2025 [24][25]. Explicitly **not** an OTel API or SDK [26]. Declares `platforms: [.macOS("13.0")]` and uses gRPC Swift v2 [24][26]. | **No.** Server-side Swift only. Would become relevant only if we ship a Linux companion server. |

The maintainers of `swift-otel` say this themselves: "For folks that prefer to use the OTel
APIs for recording telemetry and/or to use an OTel SDK directly, then the `opentelemetry-swift`
will be the right choice" [25]. In the 1.0 API review thread, a "telemetry from mobile device"
use case was described as "riddled with concerns" and explicitly declined as out of scope
[27]. So the question "opentelemetry-swift or swift-otel?" has a clean answer for us:
`opentelemetry-swift`. `swift-otel` is the wrong repository for an iOS app.

### Maturity

Signal status, per the OTel Swift docs and the package README:

| Signal | opentelemetry.io status | README status |
|---|---|---|
| Traces | **Stable** [3] | "Tracing and Baggage are considered stable" [4] |
| Metrics | Development [3] | "implemented using an **outdated spec**, is fully functional but **will change**" [4] |
| Logs | Development [3] | "considered **beta quality**" [4] |

This is the load-bearing maturity finding. **Traces are safe to build on. Metrics are not a
stable contract in this SDK, and Logs are not either.** Any requirement that depends on OTel
metrics or logs API stability must be written to tolerate a breaking change.

### Project health

- Three maintainers: Ariel Demarco (Embrace), Bryce Buchanan (Elastic), Ignacio Bonafonte
  (independent) [8][23].
- Weekly SIG, Thursdays 09:00 PT, `#otel-swift` on CNCF Slack, formally registered as an
  implementation SIG in `open-telemetry/community` [28][8].
- Release cadence is real: 2.4.1 (May 2026), 2.5.0 (Aug 2026), 2.5.1 (Aug 2026) [22].
- ~360 stars, ~123 open issues [11]. Small, but not abandoned.
- CocoaPods is being deprecated on a published timeline (final pod release by 30 Sept 2026,
  support ends 2 Dec 2026); **SPM is the only forward path** [29]. Fine for us — we are SPM-only
  by premise.

Mobile-specific instrumentation is the weak spot, and the project is candid about it. An open
issue tracks the gap against `opentelemetry-android`: crash instrumentation, view lifecycle,
startup, slow rendering, view interaction and `os.log`→OTel-logs bridging are all listed as
missing or in progress [9]. MetricKit instrumentation exists but Apple rebuilt MetricKit for
iOS 27 with a new `MetricManager` API and the SDK has not yet adapted [30].

**This does not hurt us.** We do not want auto-instrumentation. We want *manual* spans around
a pipeline we wrote, which is precisely the part that is stable.

### Platform support

`opentelemetry-swift-core` declares `.macOS(.v10_13), .iOS(.v12), .tvOS(.v12), .watchOS(.v4),
.visionOS(.v1)` and its only declared dependency, `swift-atomics`, is conditionally applied
`.when(platforms: [.linux])` — so **on Apple platforms the API+SDK has no transitive
dependencies at all** [1]. Contributors confirmed a watchOS 4 build works [31]. This is
better than the ecosystem's reputation suggests and it removes the "does it even run on
watchOS" concern.

### Dependency weight and binary size

This is where the real cost sits, and it is entirely about exporters.

- The full `opentelemetry-swift` package historically pulled in `grpc-swift`, `swift-nio`
  (and its ssl/http2/extras/transport-services siblings), `SwiftProtobuf`, `Thrift-Swift`,
  `Opentracing`, `Reachability.swift`, `swift-atomics`, `swift-system`, `swift-metrics`,
  `swift-http-types` [12][10].
- Maintainers' position is that unused targets are not linked into the final product [10];
  Datadog measured a real app going from 33.6 MB to 37.5 MB when adding OTel support, which
  they judged acceptable [12]. **Treat ~4 MB as the order of magnitude for a naive
  integration, not a measured figure for our shape.** [assumption]
- Datadog subsequently migrated `dd-sdk-ios` off their own mirror onto the official
  `opentelemetry-swift-core` specifically because the split fixed the dependency-weight
  problem [5].
- OTLP/HTTP requires `SwiftProtobuf`. OTLP/gRPC requires `grpc-swift` + NIOPosix, which one
  contributor measured as adding "many minutes" of compile time [11].

**Conclusion: OTLP/HTTP+protobuf only. gRPC is vetoed.** Note the counter-argument honestly:
the README says OTLP/gRPC is "production ready" and OTLP/HTTP is "still experimental" [4].
I am recommending the *less mature transport* on dependency-weight and watchOS grounds. That
is a deliberate trade and the PM should see it as one. Mitigation: HTTP export is optional and
non-default, so a transport bug degrades an opt-in feature rather than the product.

### Licence

`opentelemetry-swift` and `opentelemetry-swift-core`: **Apache-2.0** [11]. `swift-log`:
Apache-2.0. `swift-otel`: Apache-2.0. No licence obstacle to an open-source app under any
common OSI licence.

### One more gap worth knowing

`opentelemetry-swift` does **not** implement the standard OTel environment-variable
configuration scheme. `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME`,
`OTEL_RESOURCE_ATTRIBUTES` and `OTEL_TRACES_SAMPLER` are ignored; only `OTEL_EXPORTER_OTLP_HEADERS`
is parsed [6]. Irrelevant on iOS (no env vars in production anyway) but it means any
documentation we write for self-hosters cannot lean on the OTel-standard env var story.
[Source is a vendor documentation page, not an OTel primary source — treat as
**medium confidence** and re-verify at Stage 2.]

---

## Logging framework assessment and recommendation

### Recommendation

**`os.Logger` (Apple unified logging) as the only logging API in app targets. No `swift-log`
facade in v1. A separate, schema-constrained durable diagnostic journal for anything that
must survive process death.**

### The comparison

| | `os.Logger` / OSLog | `swift-log` (SSWG) | App-owned journal |
|---|---|---|---|
| Availability | iOS 14+, all Apple platforms [32] | All platforms incl. Linux | Ours |
| Structured metadata | **No `metadata` field** [17] | Yes, `Logger.Metadata` | Yes, closed schema |
| Privacy annotations | **Yes — `%{private}` is the default for dynamic strings; `%{public}` is opt-in** [32][16] | **No** | Enforced by allowlist |
| Redirectable to a custom backend | **No** — system path only [17] | Yes, that is its purpose | N/A |
| Retrieval of *current process* logs on-device | Yes, `OSLogStore(scope:.currentProcessIdentifier)`, no entitlement since iOS 15 [16][13] | Depends on handler | Yes |
| Retrieval of *previous process* logs on iOS | **No** [13][14][15] | Depends on handler | Yes |
| Debug-level persistence | Not persisted by default; needs `OSLogPreferences` in Info.plist [33] | Handler's choice | Configurable |
| Performance | Deferred/lazy formatting, designed for always-on use [32] | Depends; the os_log backend eagerly interpolates [18] | Ours to measure |
| OTel interop | No official bridge; `os.log`→OTel-logs listed as *missing* in OTel Swift [9] | `swift-otel` bridges it, but macOS 13+ only [24] | Direct — we emit OTel from it |

### Why `os.Logger` wins on Apple platforms

Apple's `swift-log` README carries an explicit warning about the os_log backend it links: it
"always uses `%{public}@` as the format string and eagerly converts all string interpolations
to Strings", causing (1) loss of performance and (2) "makes all messages public, which
changes the default privacy policy of os_log, and doesn't allow specifying fine-grained
privacy of sections of the message" [18][16]. A Swift corelibs maintainer confirmed on the
forums that this is still true, that the Apple-platform `Logger` "cannot be redirected to
other logging backends", and that "it is still true that you should not encapsulate the
system logger on Apple platforms" [17].

For a *health data* app, point (2) is disqualifying. `os.Logger`'s default-private behaviour
for dynamic values means a developer who writes `logger.error("failed for \(sampleType)")`
gets redaction *by default* and has to consciously type `privacy: .public` to leak. That is
the correct failure direction, and it is the only place in our stack where the platform gives
us privacy-by-default for free. `swift-log` gives us the opposite default.

### Where the recommendation is a close call

Three places, and I want them on the record:

1. **`os.Logger` has no structured metadata.** Every field we care about has to be
   interpolated into a message string, which makes the logs unqueryable-by-field and makes
   automated redaction verification harder. `swift-log`'s `Logger.Metadata` is genuinely
   better for our use case *in isolation*. My resolution — put structure in the journal, not
   in the log lines — sidesteps this rather than solving it, and it means we maintain two
   emission paths. That is a real cost.
2. **A cross-platform core package changes the answer.** If we ever build a shared Swift
   package that must compile on Linux — a companion server, a CLI, a Grafana-side component —
   then that package should use `swift-log`, because `os.Logger` does not exist there. My
   recommendation is scoped to *app targets*. A facade is over-engineering **inside the iOS
   app**; it is correct **in a Linux-capable package**. If the PM decides we ship a companion
   server in v1, revisit.
3. **`OSLogPreferences` makes verbose logging a real workflow.** Debug-level entries are not
   persisted by default and largely do not appear via `OSLogStore`; adding an `OSLogPreferences`
   dictionary with `Enable`/`Persist` set to `Debug` (and optionally `Enable-Private-Data`)
   makes them available [33]. This is a genuinely useful "reproduce with verbose logging on"
   capability — but `Enable-Private-Data` defeats `%{private}` redaction wholesale and must
   **never** ship in a release build. Flagging it for the security engineer as a
   build-configuration hazard.

### Is a facade warranted?

**No, in v1, for app targets.** A facade over `os.Logger` cannot preserve the privacy
annotations (they are compile-time string-interpolation machinery, not runtime arguments), so
the facade would have to reimplement them, which the forum thread describes as needing to
"emulate the string interpolation feature... held very carefully to not have poor logging
performance" [17]. That is a meaningful amount of tricky infrastructure to build in a
greenfield app, in exchange for portability we do not yet need. Over-engineering.

**Not mutually exclusive, as the brief notes** — and the resolution is that they occupy
different roles rather than layering:

- **Tier 1, `os.Logger`:** free-form developer diagnostics, privacy-annotated, transient,
  visible in Xcode / Console.app / `sysdiagnose`, retrievable in-app for the *current process
  only*. Never the source of truth.
- **Tier 2, the diagnostic journal:** a small, closed, versioned schema of pipeline events.
  Durable across process death and app relaunch. This is what the export-history UI reads,
  what the diagnostic bundle serialises, and what OTLP export projects from. Not a log
  framework; a domain event store with a fixed vocabulary — which is exactly why redaction is
  verifiable by construction rather than by developer discipline.

---

## Signal taxonomy: traces, metrics, logs

### Traces — span taxonomy

One root span per export run, with a closed set of child span names. **Span names come from
a fixed enum; variable data goes in attributes.** This is the first cardinality rule.

| Span name | Kind | Parent | Purpose |
|---|---|---|---|
| `export.run` | INTERNAL | root | The whole run for one destination. Carries outcome. |
| `export.discover` | INTERNAL | `export.run` | Determine which types/date ranges are due; read the anchor/watermark. |
| `export.query` | INTERNAL | `export.run` | One HealthKit query. One span **per query**, type in an attribute. |
| `export.transform` | INTERNAL | `export.run` | Domain mapping / summarisation / grouping. |
| `export.serialise` | INTERNAL | `export.run` | Encode to JSON / CSV / GPX / NDJSON. |
| `export.transmit` | CLIENT | `export.run` | The network operation. **Attributes deliberately non-conformant — see below.** |
| `export.acknowledge` | INTERNAL | `export.run` | Interpret the destination's response as accepted / rejected / unknown. |
| `export.commit` | INTERNAL | `export.run` | Advance the watermark. Separate from acknowledge on purpose: this is where "sent but not recorded as sent" duplicates come from. |
| `export.retry` | INTERNAL | `export.run` | A retry attempt. Attempt number in an attribute. |

Deliberate additions to the taxonomy the brief listed: `export.commit` (the watermark
advance) and a `heartbeat` outcome on `export.run`. Both exist because the incumbent's worst
bug is a false success [21], and both of those steps are where a false success is
manufactured.

### The semconv deviation we must take on purpose

`export.transmit` is an HTTP client span. Stable HTTP semantic conventions make
`http.request.method` and `server.address` required, and expect `url.full`, `server.port`,
`http.response.status_code` [34]. **`server.address`, `server.port` and `url.full` are exactly
the fields that reveal which clinic, CGM vendor, insurer or hospital endpoint a person sends
their health data to.** A hostname is a diagnosis hint.

Requirement position: we emit `http.request.method` and `http.response.status_code` (both
safe), and we **omit** `server.address`, `server.port`, `url.full`, `url.path`, `url.query`
and all request/response headers. We substitute `ohe.destination.kind` (a closed enum) and
`ohe.destination.id` (a locally-generated opaque UUID, stable per configured destination,
meaningless off-device).

Consequence, stated loudly: **we cannot use `URLSessionInstrumentation` from
`opentelemetry-swift`.** Its purpose is to auto-populate the attributes we are forbidding.
Automatic HTTP instrumentation is incompatible with our privacy posture and must be
explicitly disabled, not merely unconfigured.

For MQTT destinations, messaging semconv is still Development status and `mqtt` is not even a
registered `messaging.system` value [35][36], so there is little to conform to. We use
`messaging.operation.name` and omit `messaging.destination.name` — **the MQTT topic string is
user-authored and routinely contains names, room names and device names.**

### Attributes with diagnostic value

All of these are either boolean, numeric-bucketed, or drawn from a closed enum.

**On `export.run`:**
- `ohe.export.trigger` ∈ {`manual`, `observer_query`, `bg_app_refresh`, `bg_processing`,
  `shortcut`, `widget`, `app_foreground`, `watch_companion`} — *the single most valuable
  attribute we have*, because it separates "we ran and failed" from "the OS never woke us".
- `ohe.export.outcome` ∈ {`success`, `success_nothing_due`, `partial`, `failed`,
  `abandoned_no_budget`, `cancelled_by_system`, `unknown_ack`}
- `ohe.destination.kind` ∈ {`rest`, `mqtt`, `home_assistant`, `file`, `icloud_drive`,
  `local_server`, `calendar`}
- `ohe.destination.id` — opaque local UUID
- `ohe.export.format` ∈ {`json`, `csv`, `gpx`, `ndjson`}
- `ohe.export.mode` ∈ {`delta`, `full`, `backfill`}
- `ohe.export.types_count`, `ohe.export.samples_read`, `ohe.export.samples_sent`,
  `ohe.export.samples_acked` — **counts, never values.** The gap between read and acked is
  the silent-failure detector.
- `ohe.device.locked_during_run` (bool) — see hard constraint HC-1
- `ohe.device.low_power_mode` (bool), `ohe.device.charging` (bool)
- `network.connection.type` ∈ {`wifi`, `cell`, `wired`, `unavailable`} (semconv)
- `ios.app.state` (semconv, Development) [37]
- `error.type` (semconv, stable) — set from **our** closed error taxonomy, never from
  `error.localizedDescription`
- `ohe.error.class` — closed enum: `healthkit_locked`, `healthkit_unauthorized`,
  `healthkit_no_data`, `healthkit_query_timeout`, `healthkit_partial_read`,
  `transform_failed`, `serialise_failed`, `transport_dns`, `transport_tls_trust`,
  `transport_tls_handshake`, `transport_timeout`, `transport_refused`, `transport_http_4xx`,
  `transport_http_401_403`, `transport_http_413`, `transport_http_5xx`, `mqtt_unreachable`,
  `mqtt_not_authorised`, `ack_absent`, `ack_rejected`, `budget_exhausted`, `disk_full`,
  `config_invalid`, `cancelled_by_system`, `unknown`.

**On `export.query`:**
- `ohe.health.type` — the `HKObjectType` identifier string. Bounded by Apple's closed
  enumeration (~150 values per the reference product's advertised surface), so acceptable as
  a *span* attribute. **Restricted as a metric dimension — see cardinality.**
- `ohe.query.anchored` (bool), `ohe.query.range_days` (bucketed: 1, 7, 30, 90, 365, >365)
- `ohe.query.samples` (count)

### Session and resource

`session.id` and `session.previous_id` per semconv, both `Opt-In` and Development status
[37][38]. Position: generate a session ID **local-only by default**, and **strip it from any
egress to the user's collector unless the user turns it on**, because a device-stable
correlator is exactly the kind of thing that turns anonymous telemetry into a device
fingerprint. Never include it in a maintainer-bound signal under any circumstances.

Resource attributes: `service.name`, `service.version`, `os.name`, `os.version`,
`device.model.identifier`. **Not** `device.id`, not IDFV, not an install UUID in any
maintainer-bound signal.

### Metrics

| Metric | Type | Unit | Dimensions | Notes |
|---|---|---|---|---|
| `ohe.export.runs` | Counter | `{run}` | `trigger`, `destination.kind`, `outcome` | 8 × 7 × 7 = 392 max |
| `ohe.export.duration` | Histogram | `s` | `destination.kind`, `phase` | 7 × 9 = 63 |
| `ohe.export.samples` | Counter | `{sample}` | `destination.kind` (+ `health.type` **opt-in**) | see budget |
| `ohe.export.payload.size` | Histogram | `By` | `destination.kind`, `format` | 28 |
| `ohe.export.retries` | Counter | `{attempt}` | `error.class` | 25 |
| `ohe.export.errors` | Counter | `{error}` | `error.class`, `destination.kind` | 175 |
| `ohe.destination.staleness` | Gauge | `s` | `destination.id` | **the primary SLI** |
| `ohe.destination.last_success.timestamp` | Gauge | `s` (epoch) | `destination.id` | for the user's own alerting |
| `ohe.background.wake` | Counter | `{wake}` | `trigger`, `outcome` | divergence from `export.runs` = scheduling failure |
| `ohe.healthkit.query.duration` | Histogram | `s` | (+ `health.type` **opt-in**) | |
| `ohe.telemetry.dropped` | Counter | `{item}` | `signal`, `reason` | self-observability; must exist |

### Cardinality discipline

This is where mobile telemetry usually goes wrong, so it gets hard numbers rather than
guidance.

**Rules:**
1. Every metric attribute **value** must come from a compile-time-closed enumeration. There
   is no path by which a runtime string becomes a metric dimension value.
2. A runtime guard replaces any unrecognised value with the literal `other` and increments
   `ohe.telemetry.dropped{reason="unknown_attribute_value"}`. Fail-safe, not fail-open.
3. **Never a metric dimension:** sample UUID, sample timestamp, sample value, hostname, URL,
   MQTT topic, file path, `session.id`, trace/span IDs, retry sequence number, user-authored
   destination name, `HKSource` / device name, OS error code, error message.
4. `ohe.health.type` (~150 values) is **off by default** as a metric dimension. Enabling it
   multiplies the affected metrics by ~150 and is a user-visible toggle with a stated cost.
5. **Budget: ≤ 500 active time series in the default local configuration; ≤ 2,500 with
   `health.type` enabled.** Enforced by a build-time test that enumerates the cross-product
   of every declared metric's declared dimensions and fails the build if the product exceeds
   the cap.
6. Span attributes are allowed higher cardinality than metric dimensions (they are not
   aggregated), but the *forbidden list* in rule 3 applies to spans too, minus trace/span IDs
   and `session.id`.
7. Histogram bucket boundaries are fixed at declaration and never derived from data.

**Assumption [assumption]:** 500 series is a comfortable ceiling for on-device aggregation
and for a hobbyist Prometheus/Mimir instance receiving data from a handful of family devices.
If the self-hoster audience turns out to run genuinely large collectors this is
conservative — but conservative is the right error direction and the budget is a config knob,
not a hard-coded law.

### Logs and events

Two distinct things, and conflating them is a trap:

- **`os.Logger` output** — free-form, privacy-annotated, current-process-only, not a stable
  contract, not exported anywhere, not in the bundle beyond the current process.
- **Journal events** — closed schema, durable, versioned, the thing that becomes OTel
  LogRecords / span events if the user opts into OTLP. Because OTel Logs in Swift is beta
  quality [4], v1 should map journal events to **span events** on the run span rather than to
  the OTel Logs API, which is both more mature and semantically honest (they *are* events
  within a run).

### OTel on a device that is asleep most of the time

This is the constraint set that most OTel-on-mobile advice ignores.

**Batching and buffering.** Default `BatchSpanProcessor` behaviour — a timer-driven periodic
export — is wrong on iOS: the timer does not fire while suspended, and if it does fire during
a background wake it competes for the wake budget with the actual work. Requirement: telemetry
export is **opportunistic and never scheduled** (OBS-19).

**Surviving process death.** `opentelemetry-swift` ships a `PersistenceSpanExporterDecorator` /
`PersistenceLogExporterDecorator` / `PersistenceMetricExporterDecorator` that writes exported
data to disk, then reads it back and forwards it later — explicitly designed for "mobile apps
that operate while the device has no network connectivity... possibly after the app is
terminated and relaunched" [39][40]. This is a real, cited capability and it is the right
mechanism. Two caveats: the reference implementation stores under `.cachesDirectory`, which
the system may purge under disk pressure [41]; and it is not a substitute for the journal,
because a persisted OTLP blob is not a thing a user can read. **The journal is the source of
truth; the persistence decorator is a delivery convenience.**

**Cold-start cost.** HealthKit background delivery only works if observer queries are
registered in `application(_:didFinishLaunchingWithOptions:)` [42][43]. Anything that delays
that method reduces our chance of getting the data at all. Requirement: telemetry
initialisation is off the launch critical path and never precedes observer registration
(OBS-20).

**Wake budget.** HealthKit notifies at most once per the registered frequency [43]; on watchOS
you get roughly four background updates an hour and only with an active complication [43];
and if the observer completion handler is not called, HealthKit backs off and **stops
delivering after three failures** [43]. Telemetry must never sit between the work and the
completion handler.

**watchOS.** No gRPC, no `NetworkMonitor` in the reference persistence setup [41]. Telemetry
on watchOS is local-only in v1.

---

## Telemetry deployment models and consent

### (a) Purely local, user-inspectable, never leaves the device — **the default**

The journal, the history UI, on-device metric aggregation, and `os.Logger`. Zero network
egress from the telemetry subsystem. No OTLP exporter constructed. No collector endpoint
configurable until the user goes looking for one.

This must be verifiable rather than asserted: `NSPrivacyTracking = false`, an empty/absent
`NSPrivacyTrackingDomains` [44][45], and an automated network-isolation test.

### (b) Exported to the *user's own* OTel collector

Genuinely attractive for the self-hoster audience, and the most OTel-shaped feature in the
product. This is where the owner's instinct pays off: someone already running Grafana,
Prometheus, Tempo or an OTel Collector gets our spans and metrics in their existing stack for
free, and can build their own alerting on `ohe.destination.staleness`.

Non-negotiables:
- Opt-in, off by default, per-install.
- **The same redaction rules as local.** There is no "verbose mode" that unlocks health data
  for egress. The allowlist does not have a bypass. If a user wants their health data at that
  endpoint, that is what the *export* feature is for — and it goes through consent, history
  and destination configuration like any other destination.
- TLS required. Plain HTTP permitted only for RFC1918 / link-local / `.local` / loopback
  addresses, and only after an explicit typed acknowledgement.
- A **payload preview** before enabling: the literal bytes of a representative export, shown
  on screen, scrollable, copyable.
- A **published, versioned attribute schema** in the repository listing every attribute we
  can ever emit, its type, its domain, and whether it is health-derived. Auditable by the
  people whose data it is — which is the project's stated differentiator.
- `session.id` stripped unless separately enabled.

### (c) Aggregated crash/error reporting to the project maintainers

**Recommendation: Won't (v1). And I would argue Won't, permanently, as an automatic channel.**

The reasoning, rigorously:

1. **App Store 5.1.3(i)** prohibits using or disclosing to third parties data gathered in the
   health/fitness context for "advertising, marketing, or other use-based data mining
   purposes other than improving health management", and Apple's HealthKit privacy guidance
   states you "must not disclose any information gained through HealthKit to a third party
   without express permission from the user" — and even with permission, only to third parties
   who "also provide a health or fitness service to the user" [46][47][48]. The project
   maintainers provide no health service. Debug telemetry from a health-export pipeline sits
   uncomfortably close to that line even after redaction, and App Review will read the app's
   *category* before it reads our allowlist.
2. **5.1.3(ii)** additionally forbids storing personal health information in iCloud [46][48].
   That constrains where the journal lives and what gets backed up, independently of (c).
3. **Operating an endpoint makes the project a data controller.** Under GDPR, health data is
   Article 9 special-category data. An endpoint receiving telemetry from a health app invites
   the argument that the telemetry is health-adjacent even when it contains no samples. That
   brings a lawful-basis question, a retention policy, a breach-notification duty, a DPIA, a
   hosting bill and an ingest credential that must ship inside a public repository. An
   unfunded OSS project cannot credibly discharge any of that, and pretending otherwise is
   worse than not doing it.
4. **Redaction bugs are irreversible.** The whole design rests on an allowlist. The day the
   allowlist has a hole and a `partial_read` error carries a fragment of a payload, that
   fragment is on maintainer infrastructure and cannot be un-received. Every other model in
   this document fails *safe* — the data stays on the device. This one fails *catastrophically*.
5. **The legitimate need is already met.** For App Store builds, Apple already gives
   maintainers aggregated crash reports via Xcode Organizer and App Store Connect, mediated
   by Apple's own consent flow, with no code from us. On-device, MetricKit supplies crash and
   hang diagnostics we can surface locally [30]. And the diagnostic bundle (§ below) gives
   maintainers *better* data than aggregate telemetry would — a full run history from a user
   who is actively motivated to help — with consent that is unambiguous, contemporaneous and
   reviewed by the person giving it.

**The honest alternative** is therefore: user-initiated, user-reviewed diagnostic bundles
attached to GitHub issues, plus Apple-mediated crash reporting for store builds. We lose
fleet-wide error-rate visibility. I think that is the correct price and the PM should accept
it explicitly rather than discover it later (see Open Questions).

**If the PM overrules me,** the hard floor is OBS-27: a separate consent (never bundled with
onboarding, HealthKit authorisation, or any other permission), off by default, a strict
allowlist with zero health-derived attributes, no device-stable identifier of any kind
(including `session.id`), no destination information at all, published retention ≤ 30 days, a
public schema, a remote kill switch, declaration in the privacy manifest and nutrition label,
a published DPIA — and it must be a **physically separate pipeline** with its own serialiser,
so that a defect in the local or user-collector path cannot leak into it.

### Should the app treat its own telemetry as just another export destination?

**Conceptually yes — and we should present it that way. Architecturally no — and we must not
implement it that way.** Both halves matter.

**The case for unification.** It is elegant and it is honest. The user gets one list of
everything that leaves their device, one consent model, one revocation gesture, and — crucially —
**telemetry egress itself appears in the export history**, so "what left my device and when"
covers the observability system too. A privacy-first product that exempts its own telemetry
from its own audit trail has a credibility hole. This argument is strong and I think it wins
at the UX layer outright.

**The case against, at the implementation layer,** is three concrete failure modes:
1. **Feedback loop.** If telemetry travels the instrumented transmit path, a failing
   destination produces error spans → which produce a telemetry export → which traverses the
   failing transport → which produces more error spans. Under a network partition this is
   unbounded. Telemetry egress must generate no telemetry.
2. **Serialiser contamination.** A shared serialisation path between health payloads and
   telemetry payloads is one refactor away from putting a health payload in the telemetry
   stream. Physical separation of the two serialisers is the cheapest insurance we can buy
   against the single worst outcome in this project.
3. **Divergent failure semantics.** A dropped health export must be retried and must block
   the watermark. A dropped span must be discarded and must never block anything. Same
   pipeline, opposite correctness requirements.

**Resolution (OBS-24):** telemetry is a first-class, revocable entry in the destination list
and its egress is recorded in the export history, but it runs on an isolated pipeline with
its own serialiser and buffer, shares no code with health-payload serialisation, and is
excluded from instrumentation.

---

## Trace propagation across the user trust boundary

### Should we propagate W3C `traceparent` to user destinations?

**Yes, as a per-destination opt-in that is off by default. Never `tracestate`. Never
`baggage`. And never *accept* an inbound one.**

### The actual benefit for a self-hoster

Real and specific. A user running our app plus their own REST endpoint plus an OTel Collector
can join the phone-side `export.transmit` span to their server-side receive span in a single
trace, and answer "the phone says it sent 400 samples and my server says it got 12 — where
did they go?" without correlating by wall-clock. For the subset of our audience that already
runs a collector, this is the highest-value observability feature in the product. It is also
the one feature that *requires* OTel rather than merely benefiting from it, which is worth
noting given the owner's direction.

### What it leaks

The header content itself is low-risk by construction: W3C requires that `traceparent` MUST
NOT contain PII and that trace IDs be generated by a random number generator that MUST NOT
use potentially personally identifiable input or seed state [49][50]. A conformant
`traceparent` is a random 16-byte trace ID, a random 8-byte span ID, and flags.

The leaks are second-order, and W3C names them:

1. **Correlatability.** "A downstream service may track and correlate two or more requests
   made in a single transaction and may make assumptions about the identity of the caller"
   [49][50]. For us: the destination operator, *and any intermediary* — reverse proxy, CDN,
   ingress, corporate TLS-terminating middlebox — can link the requests of one export run,
   and across runs can begin to fingerprint a device by trace-emission pattern. When the
   destination is the user's own Raspberry Pi this is nothing. When it is a clinic portal or
   an employer wellness endpoint, it is not nothing.
2. **Stack fingerprinting.** "the `tracestate` header may imply the version of monitoring
   software used by the caller... could potentially be used to create a larger attack" [51].
   The mere presence of `traceparent` advertises that we run OTel.
3. **`tracestate` as an accidental data channel.** W3C advises that application owners
   "either ensure that no proprietary or confidential information is stored in `tracestate`,
   or... ensure that `tracestate` isn't present in requests to external systems" [51]. We
   take the second option: we never send it.
4. **Response echo.** If a destination echoes trace headers back, those values "may
   inadvertently be passed to cross-origin callers" [49]. Not our bug, but a reason to keep
   the surface minimal.
5. **Breakage.** Header-strict endpoints and CORS-restricted paths can reject requests
   carrying unexpected headers; W3C explicitly warns to test every code path that sends these
   headers [51]. For us that means propagation must never be able to turn a working export
   into a failing one — hence: off by default, per destination, and automatically disabled
   with a history entry if a request succeeds without the header and fails with it.

### Where the trace terminates

**By default, at the device boundary.** The device-side root span *is* the whole trace; there
is no remote parent and no remote child. Turning propagation on for a specific destination
extends the trace exactly one hop, to whatever that destination does with it — which is
outside our control and outside our promises, and the UI must say so in those words.

**Asymmetry requirement (OBS-16).** We may *emit* `traceparent`. We must never *continue* an
inbound one. If we build the local TCP/HTTP read server that the reference product has, an
inbound `traceparent` must be dropped, not adopted. W3C's security section describes exactly
why: naively continuing any trace with the `sampled` flag set lets an attacker "overwhelm an
application with tracing overhead, forge trace-id collisions that make monitoring data
unusable" [51]. On a battery-powered device, denial-of-monitoring is also denial-of-battery.

**Sampling.** The `sampled` flag must reflect our actual local sampling decision. Do not
always set it to advertise interest we do not have. **Local default: sample everything** — an
export run happens a handful of times an hour at most, so head sampling buys nothing and
costs diagnosability. Introduce sampling only for the user-collector path, and only if volume
proves to be a problem.

---

## User-facing observability: export history and diagnostics

**This outranks OTel in v1 priority. I am stating that as a position, not hedging it.**

The evidence is the incumbent. Health Auto Export's published troubleshooting guidance is
entirely built on two features: per-automation **Activity Logs** ("Events are grouped by run,
newest runs first... Warnings mean the run completed but a step took longer than expected.
Errors mean a step failed") and a shareable **App Event Logs diagnostic ZIP** [19][20]. Its
error text already distinguishes the cases we care about — "No health data was found in this
date range, so nothing was uploaded" versus "Health data could not be fully read. The device
may have locked during the export. Nothing was uploaded" [20]. That second string is a plain
-language rendering of `errorDatabaseInaccessible`, and it is the right way to talk to a user.

And the failure mode to beat is documented in its own issue tracker: a run showing status
**"Succeeded"** while no data reached the user's Home Assistant [21]. That is a *false
success*, and it is a data-model bug — the run recorded "we sent" as "it arrived". No
telemetry backend fixes that. A history model that separates *sent*, *acknowledged* and
*committed* does, by construction.

So the ranking, plainly: **journal + history + bundle first; OTLP-to-user-collector second;
maintainer aggregation never.** If the PM has to cut something to make v1, cut OTLP export,
not the history. The history is the differentiator; OTLP is the differentiator *for the
subset of users who run a collector*, which is a smaller set than the brief's "self-hoster
friendly" framing implies. [assumption]

Requirements are OBS-01 through OBS-09.

Two points that are easy to miss:

- **The bundle must work when the app is broken.** No network, HealthKit authorisation
  revoked, configuration corrupt, journal partially unreadable. If bundle generation depends
  on the pipeline it is diagnosing, it will be unavailable in exactly the cases we need it.
- **The user must see the bundle contents before sharing.** Not a summary — the actual
  contents, rendered as readable text, scrollable. This is the mechanism that makes consent
  real and it is also our best defence against a redaction bug, because thousands of users
  reading their own bundles will find holes that our tests missed.

---

## Service level objectives and silent-failure detection

"The service" is the user's own pipeline. These SLOs are **per install and per destination,
evaluated on-device**, and they are the input to silent-failure detection. There are
deliberately no project-wide aggregates, because by design we will have no data with which to
compute them.

| ID | SLO | Target | Window | Notes |
|---|---|---|---|---|
| SLO-1 | Export success rate | ≥ 99% of *attempted* runs per destination end `success` or `success_nothing_due` | rolling 7 days | Excludes runs the OS never scheduled — those are SLO-4's business |
| SLO-2 | Freshness | `now − last_successful_ack` ≤ `max(2 × interval, 90 min)` at p95 | rolling 7 days | Alarm threshold `max(4 × interval, 6 h)` |
| SLO-3 | Delivery completeness | `samples_acked == samples_read` for 100% of `success` runs | every run | **Zero tolerance.** Any deficit forces `partial`, never `success` |
| SLO-4 | Scheduling health | `background_wakes ≥ 50%` of expected wakes per destination | rolling 7 days | Distinguishes "OS never woke us" from "we failed" |
| SLO-5 | Silent-failure detection latency | user-visible signal within ≤ 60 min of the SLO-2 alarm threshold being crossed | per incident | Watchdog independent of the pipeline |
| SLO-6 | Time to diagnosis | error class + remediation text reachable in ≤ 3 taps from launch, for any run in history | per release | Falsifiable via a scripted usability walkthrough |
| SLO-7 | Observability overhead | ≤ 2% of run wall-clock, ≤ 5 MB durable storage at default retention, ≤ 30 ms added cold start, **0 bytes network in default config** | per release | Measured in CI on a physical device |

**Why SLO-3 has zero tolerance.** It is the direct antidote to the incumbent's false-success
bug [21]. `success` must mean "the destination told us it has the data", not "we finished
calling `write`". Where a destination cannot acknowledge — fire-and-forget MQTT QoS 0, a file
write to a synced folder — the outcome is `unknown_ack`, a *third* state, surfaced as such,
never collapsed into success. This is a data-model requirement, not a UI one.

**Why SLO-4 exists separately.** A large share of real-world failures are the OS declining to
wake us: HealthKit background delivery is rate-limited by registered frequency [43], watchOS
allows roughly four wakes an hour and only with an active complication [43], and the incumbent's
own help pages advise users to charge the device and add a Home Screen widget to get more
background execution [19][20]. We cannot fix that. We can *name* it, which is the difference
between "this app is broken" and "iOS has not woken this app since Tuesday; here is why, and
here are the two things that help". Wrongly attributing a scheduling failure to a transport
failure sends the user to debug their server for nothing.

### Silent-failure detection as a first-class requirement

Five mechanisms, all in the requirements table:

1. **An independent watchdog** (OBS-10) that evaluates staleness per destination and is not
   part of the export pipeline — so a wedged pipeline cannot suppress its own alarm. Must
   also fire on app foreground, so it works even when background execution is fully denied.
2. **Heartbeat runs** (OBS-11). A run with nothing to send still records
   `success_nothing_due` with a timestamp. Without this, "no new health data" is
   indistinguishable from "broken", and freshness is unmeasurable.
3. **Escalation** (OBS-12): in-app badge → local notification → widget / watch complication
   showing last-success age in plain words ("Last export: 3 days ago"). Note the incumbent
   recommends a widget partly as a background-execution *trick* [19]; we should ship one as
   an honest status surface, and get the scheduling benefit as a side effect.
4. **Trigger-vs-run divergence** (OBS-13). `ohe.background.wake` versus `ohe.export.runs`
   detects the scheduling-failure class specifically, and routes to different remediation text.
5. **Destination-side alerting support** (OBS-14). Emit
   `ohe.destination.last_success.timestamp` to the user's collector so their own alert rules
   can fire without reverse-engineering our schema. Publish the recommended rule *shape* as
   documentation at Stage 2+. This is the one place where the OTel investment directly buys
   silent-failure detection that the app itself cannot provide — if the phone is off, only the
   destination side can notice.

---

## Requirements I own

| ID | Requirement | Priority | Rationale | How we verify |
|---|---|---|---|---|
| OBS-01 | The app maintains a durable, structured **export journal** on device, surviving process termination, force-quit, relaunch and OS update. Every export run records: trigger, destination id + kind, start/end time, per-phase durations, per-type sample counts (read / sent / acked), outcome, error class, retry state and next scheduled attempt. | **Must** | `OSLogStore` on iOS cannot read a previous process's entries [13][14][15], so os_log alone cannot answer "why did it fail three days ago". | Automated: write a run, kill the process (SIGKILL), relaunch, assert the run is present and complete. Repeat across an OS-version upgrade in a manual release check. |
| OBS-02 | Journal retention ≥ 90 days **or** ≥ 1,000 runs, whichever is reached first, with a bounded on-disk footprint. | **Must** | "Three days ago" is the stated use case; 90 days covers intermittent failures. | Automated: synthesise 1,200 runs over 120 simulated days; assert retention policy holds and total size ≤ 5 MB. |
| OBS-03 | An **export history UI** lists runs newest-first, groups events within a run, and shows for each run in plain language: what was sent, when, to which destination (by the user's own label), and — on failure — why and what to do. | **Must** | Directly matches the incumbent's most-used support surface [19][20] and the brief's "see why an export failed". | Manual review against a fixture set covering all 25 error classes; every entry legible without jargon by a non-technical reader. |
| OBS-04 | Run outcomes distinguish at minimum `success`, `success_nothing_due`, `partial`, `unknown_ack`, `failed`, `abandoned_no_budget`, `cancelled_by_system`. A run whose acknowledged sample count is less than its read count **may never** be recorded as `success`. | **Must** | The incumbent's worst documented bug is a "Succeeded" run that delivered nothing [21]. | Automated: an integration test with a destination that accepts the connection and silently discards the body asserts outcome is `partial` or `unknown_ack`, never `success`. |
| OBS-05 | A **closed error catalogue**: every failure maps to one of a fixed set of error classes, each with a localised one-sentence cause and one-sentence remediation. No raw `NSError`/`localizedDescription` reaches the UI or the journal. | **Must** | Raw error strings are both unreadable and a payload-fragment leak vector. | Automated: enumerate all error classes; assert each has non-empty cause and remediation strings in every shipped locale, and that no user-visible string consists solely of a numeric code. Reflection test asserts the journal schema has no free-text error field. |
| OBS-06 | A **redacted diagnostic bundle** generated in one action, containing: app/OS version, device model, configuration *shape* (destination kinds, formats, enabled type identifiers), the last N runs with error classes and timings, current-process `os.Logger` entries, MetricKit diagnostics if present, and the cardinality-capped metric snapshot. | **Must** | Gives maintainers real diagnostic data with unambiguous, contemporaneous consent — and removes the need for maintainer-bound telemetry entirely. | See OBS-07 and OBS-08. |
| OBS-07 | The diagnostic bundle contains **zero** health sample values, sample timestamps at sample granularity, sample UUIDs, `HKSource`/device names, destination hostnames/URLs/IPs/ports, MQTT topics, credentials, tokens, or absolute paths inside the user container. Hostnames and user-authored labels are replaced by stable local pseudonyms (`destination-1`, `host-a1b2`). **Redaction is an allowlist: a field is absent unless explicitly permitted.** | **Must** | `HKSource` names the user's medical devices; a hostname can identify a clinic. This is the project's core privacy promise. | **Canary test in CI on every commit.** Fixture seeds a known token, hostname `clinic.example.org`, sample value `42.7`, source name `Dexcom G7`, path `/var/mobile/...`, MQTT topic `home/bedroom/glucose`. Assert none appear in bundle output. Additionally a schema test asserts the allowlist is exhaustive and every new journal field defaults to excluded. |
| OBS-08 | The bundle's full contents are rendered on screen for the user to read and scroll **before** any share action is offered. | **Must** | Makes consent real, and turns the user base into a redaction-bug detector. | Manual UI review; automated assertion that no share affordance is reachable without passing through the preview. |
| OBS-09 | Bundle generation succeeds with no network, with HealthKit authorisation denied or revoked, with an invalid destination configuration, and with a partially corrupt journal (degrading to a partial bundle with an explicit note). | **Must** | A diagnostic that needs the broken subsystem is unavailable exactly when needed. | Automated: four fault-injection cases, each asserting a non-empty, well-formed bundle. |
| OBS-10 | A **staleness watchdog** independent of the export pipeline evaluates `now − last_successful_ack` per enabled destination, on app foreground and on any available background wake, and raises a user-visible signal when the SLO-2 alarm threshold is crossed. | **Must** | Silent failure is the incumbent's most-complained-about problem; a detector inside the failing subsystem cannot be trusted. | Automated: freeze the clock forward past the threshold with the pipeline stubbed as permanently failing; assert the signal is raised. Assert the watchdog raises with the export scheduler entirely disabled. |
| OBS-11 | A run with nothing due records `success_nothing_due` with a timestamp and advances the freshness clock. | **Must** | Otherwise "no new data" is indistinguishable from "broken" and SLO-2 is uncomputable. | Automated: run with an empty HealthKit fixture; assert outcome and that staleness resets. |
| OBS-12 | Silent failure escalates: in-app indicator → local notification (if permitted) → widget / watch complication showing last-success age in plain language. Escalation degrades gracefully when notification permission is absent. | **Must** | Users do not open a working exporter; the failure must find them. | Manual review of all three surfaces; automated test that the indicator appears with notifications denied. |
| OBS-13 | The app separately counts expected background wakes and actual export runs, and attributes staleness to `scheduling` (OS did not wake us) versus `execution` (we ran and failed), with different remediation text. | **Must** | HealthKit/watchOS wake budgets make scheduling failure common and unfixable by us [43]; misattributing it sends users to debug their servers for nothing. | Automated: simulate zero wakes over the window; assert cause is `scheduling` and the remediation text differs from any execution-failure text. |
| OBS-14 | When a user collector is configured, the app emits `ohe.destination.last_success.timestamp` and `ohe.destination.staleness` so the user's own alerting can detect a phone that has stopped exporting. | **Should** | The only mechanism that detects a device that is off or dead. The strongest single argument for OTel in this product. | Automated: assert both series present in captured OTLP payload with a recording collector fixture. |
| OBS-15 | Instrument the export pipeline with OpenTelemetry **traces** using `opentelemetry-swift-core`, with span names drawn from the closed set in § Signal taxonomy. Attributes drawn from closed enumerations. | **Should** | Honours the owner's direction where OTel is strongest — tracing is the only Stable signal in this SDK [3][4]. | Automated: an in-memory span exporter test asserts a full run produces the expected span tree, and that every emitted span name is a member of the declared enum. |
| OBS-16 | `traceparent` propagation to a user destination is **per-destination opt-in, off by default**. `tracestate` and `baggage` are never sent. An inbound `traceparent` (e.g. at a local read server) is never continued. Propagation auto-disables with a history entry if a request succeeds without the header and fails with it. | **Must** | W3C names correlatability, stack fingerprinting and denial-of-monitoring as the risks [49][51]; header-strict endpoints break [51]. | Automated: default config sends no trace headers (assert on a capturing test server); enabled config sends `traceparent` only; an inbound `traceparent` yields a new root trace ID; a header-rejecting server triggers auto-disable. |
| OBS-17 | Telemetry **must not** carry `server.address`, `server.port`, `url.full`, `url.path`, `url.query`, request/response headers, response bodies, MQTT topic strings, or user-authored destination labels — a deliberate, documented deviation from stable HTTP semantic conventions [34]. Automatic HTTP instrumentation (`URLSessionInstrumentation`) is explicitly disabled. | **Must** | A destination hostname can reveal where someone gets treated. Auto-instrumentation exists to populate exactly these fields. | Automated: capture all emitted spans from a full run against a destination at `https://clinic.example.org:8443/ingest?patient=7`; assert no span attribute value contains `clinic.example.org`, `8443`, `patient` or `ingest`. Dependency test asserts `URLSessionInstrumentation` is not linked. |
| OBS-18 | Metric cardinality budget: ≤ 500 active time series in default configuration, ≤ 2,500 with `health.type` dimensions enabled. Every metric attribute value comes from a compile-time-closed enumeration; unrecognised values become `other` and increment `ohe.telemetry.dropped`. | **Must** | Cardinality is where mobile telemetry reliably goes wrong; a hobbyist collector is a small collector. | Build-time test enumerates the declared cross-product and fails the build above the cap. Runtime test feeds an out-of-domain value and asserts `other` plus the dropped counter. |
| OBS-19 | Telemetry export is **opportunistic and never scheduled**: permitted only when the app is foreground, or on Wi-Fi while charging, or piggy-backed on an already-scheduled background task with spare budget. Telemetry never delays a HealthKit observer completion handler. | **Must** | HealthKit stops delivering background updates after three unacknowledged callbacks [43]; wake budget spent on telemetry is wake budget not spent on the user's data. | Automated: assert no telemetry export is initiated during a simulated background wake; assert observer completion is invoked before any telemetry work is enqueued. Instrumented test asserts telemetry adds ≤ 2% to run wall-clock. |
| OBS-20 | Telemetry initialisation is lazy and off the launch critical path, adding ≤ 30 ms to cold start, and never precedes HealthKit observer-query registration in `didFinishLaunching`. | **Must** | Observer queries must be registered in `didFinishLaunching` for background delivery to work at all [42][43]. | Automated launch-time measurement on a physical device across 20 cold starts, p95 delta ≤ 30 ms. Ordering assertion in an integration test. |
| OBS-21 | Telemetry generated during a background wake survives process termination and is delivered on a later opportunity, without loss and without duplication beyond OTLP's at-least-once semantics. | **Should** | Background failures are the failures we most need and the ones most likely to lose their evidence. | Automated: generate spans in a simulated background wake, SIGKILL, relaunch with a capturing collector, assert delivery. The journal (OBS-01) is the correctness backstop if this degrades. |
| OBS-22 | **Default posture is zero telemetry egress.** In default configuration no OTLP exporter is constructed and the telemetry subsystem opens no network connection. `NSPrivacyTracking = false`; no `NSPrivacyTrackingDomains`. | **Must** | Privacy-by-default is non-negotiable, and it must be verifiable rather than asserted. | Automated network-isolation test: run a full export cycle in default config with a loopback interceptor; assert zero connections attributable to telemetry. Static check of `PrivacyInfo.xcprivacy` in CI [44][45]. |
| OBS-23 | User-collector export (OTLP/HTTP+protobuf) is opt-in, requires TLS except for RFC1918 / link-local / `.local` / loopback with explicit typed acknowledgement, and shows a literal payload preview before enabling. The published, versioned attribute schema in the repository lists every attribute we can emit. **The same redaction rules apply as local — no bypass, no verbose mode.** | **Should** | The genuinely attractive proposition for the self-hoster audience, and the auditability that "genuinely open source" is supposed to buy. | Automated: assert a public-internet plain-HTTP endpoint is rejected; assert the emitted attribute set is a subset of the published schema (schema-conformance test in CI); manual review of the preview screen. |
| OBS-24 | Telemetry appears in the destination list and export history as a first-class, revocable destination; its egress is recorded in the history. It is implemented as an **isolated pipeline** with its own serialiser and buffer, sharing no code with health-payload serialisation, and is excluded from instrumentation. | **Must** | Unified consent and audit at the UX layer; physical isolation to prevent feedback loops and serialiser contamination. | Architecture test asserts no shared serialisation type between the two paths. Automated: assert telemetry egress produces no spans (no recursion) and does appear as a history entry. |
| OBS-25 | OTLP transport is **HTTP+protobuf only**. No gRPC, no `grpc-swift`, no SwiftNIO in any app target. | **Must** | gRPC's transitive dependency weight and compile cost [11][12]; unsuitable on watchOS. | Automated dependency-graph assertion in CI: no `grpc-swift`/`swift-nio` product in any app target. Binary-size regression gate: telemetry adds ≤ 2 MB to the app's uncompressed download size. |
| OBS-26 | On watchOS, telemetry is local-only: journal and history, no network egress, no OTLP exporter. | **Should** | No gRPC, no network monitor, four wakes an hour at best [43][41]. | Automated: watchOS target has no OTLP exporter linked; network-isolation test on watchOS. |
| OBS-27 | **No telemetry is transmitted to project-maintainer infrastructure.** No maintainer endpoint ships in v1. Maintainer-facing diagnostics come exclusively from user-initiated bundles (OBS-06) and Apple-mediated crash reporting for store builds. | **Won't** (v1) | App Store 5.1.3 and HealthKit guidance restrict third-party disclosure [46][47][48]; operating an endpoint makes an unfunded OSS project a controller of health-adjacent data; redaction bugs are irreversible; the need is already met. | Automated: assert no maintainer-controlled hostname or ingest credential exists anywhere in the source tree or built binary (string scan in CI). |
| OBS-28 | *If* OBS-27 is overruled: separate consent (never bundled), off by default, strict allowlist with zero health-derived attributes, no device-stable identifier including `session.id`, no destination information, published retention ≤ 30 days, public schema, remote kill switch, privacy-manifest and nutrition-label declaration, published DPIA, and a physically separate pipeline. | **Could** (only on PM override) | If we must, these are the terms on which it is survivable. | Every clause independently testable; the allowlist gets the same canary test as OBS-07 plus an additional assertion that the allowlist contains no health-derived field. |
| OBS-29 | `os.Logger` is the only logging API in app targets. No `swift-log` dependency in any app target. Dynamic values are `%{private}` by default; `%{public}` requires an explicit annotation. `Enable-Private-Data` must never appear in a release build's `OSLogPreferences`. | **Must** | Routing os_log through swift-log forces `%{public}@` and destroys privacy annotations [16][17][18]; `Enable-Private-Data` defeats redaction wholesale [33]. | Automated: dependency assertion that `swift-log` is absent from app targets; lint rule flagging `privacy: .public` for review; CI check that no release-configuration Info.plist contains `Enable-Private-Data`. |
| OBS-30 | The app can display and export its own current-process `os.Logger` entries, and offers a documented "verbose logging" build/configuration path via `OSLogPreferences` for reproducing an issue. | **Should** | `OSLogStore(scope:.currentProcessIdentifier)` works without entitlement from iOS 15 [16][13]; debug entries are not persisted without `OSLogPreferences` [33]. | Automated: assert current-process entries for our subsystem are retrievable on device; manual verification that debug entries appear when the verbose configuration is active and not otherwise. |
| OBS-31 | OTel metric and log **API** surfaces are used only behind a thin internal boundary owned by the project, so that a breaking change in OTel Swift's metrics or logs implementation is contained. | **Should** | OTel Swift metrics are "implemented using an outdated spec... will change"; logs are "beta quality" [3][4]. | Architecture test: no OTel metric or log type appears in the signature of any type outside the telemetry module. |
| OBS-32 | Observability overhead budget (SLO-7): ≤ 2% of export run wall-clock, ≤ 5 MB durable storage at default retention, ≤ 30 ms added cold start, 0 bytes network in default configuration. | **Must** | Observability that costs battery or launch time on a health app will be switched off, and then we have neither. | Automated performance test on a physical iPhone in CI, gating the release. |
| OBS-33 | The journal and diagnostic artefacts contain no personal health information and are therefore safe under App Store 5.1.3(ii); additionally they are excluded from iCloud backup as defence in depth. | **Must** | 5.1.3(ii) prohibits storing personal health information in iCloud [46][48]; excluding from backup means a redaction defect cannot become an iCloud disclosure. | Automated: assert the journal's storage location carries the exclude-from-backup attribute; the OBS-07 canary test doubles as the no-PHI assertion for the journal schema. |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A redaction defect puts health data or a destination hostname into telemetry or a diagnostic bundle. | Medium | **Critical** — destroys the project's core promise, irreversibly if egress occurred | Allowlist not denylist (OBS-07); canary test in CI on every commit; user-visible bundle preview (OBS-08); zero egress by default (OBS-22); no maintainer endpoint (OBS-27) so a defect cannot leave the device unnoticed. |
| `OSLogStore`'s previous-process limitation is discovered late and the team assumes `os_log` is sufficient. | **High** if not designed for now | High — the headline use case silently does not work | This is stated as HC-2 and is the reason OBS-01 exists. Verified by the kill-and-relaunch test, which fails loudly if the journal is skipped. |
| OTel Swift metrics/logs break on a spec update, or the SDK's three maintainers lose bandwidth. | Medium | Medium — churn, or a pinned-forever dependency | OBS-31 confines OTel types to one module; the journal (OBS-01) is the source of truth so OTel can be replaced without losing capability; traces (the Stable signal) are the only part we depend on structurally. |
| Cardinality explosion in a user's collector, or a user blaming us for their Prometheus falling over. | Medium | Medium — reputational, and hard to debug remotely | OBS-18 build-time budget enforcement; `health.type` dimensions off by default with a stated cost; published schema (OBS-23) so users can see the series count before enabling. |
| Telemetry consumes background wake budget and *reduces* export reliability — observability making the observed thing worse. | Medium | High — we would be causing the failure we set out to detect | OBS-19 (never scheduled, never before the completion handler); OBS-20 (off the launch path); OBS-32 overhead budget gating the release. |
| `traceparent` propagation breaks a working destination, or is later found to leak more than expected. | Low–Medium | Medium — a broken export is worse than a missing trace | OBS-16: off by default, per-destination, auto-disable on evidence of breakage, `tracestate`/`baggage` never sent, inbound never continued. |
| App Review rejects on health-data grounds due to a misread of the telemetry feature. | Low–Medium | High — blocks release | OBS-22 default zero egress; OBS-27 no maintainer endpoint; a clear, reviewable published attribute schema (OBS-23); accurate privacy manifest and nutrition label. Prepare a written review-notes explanation of the telemetry model in advance. |
| Users cannot get a bundle to a maintainer because GitHub is a barrier for non-technical people. | High | Medium — the diagnostic path exists but is unused, and OBS-27 depends on it | Share-sheet output to email/Files/Messages as well as GitHub; the bundle must be small enough to paste; the history UI must be good enough that most issues are self-diagnosed without a bundle at all. Flagged for the PM as a real weakness in my recommendation. |
| We ship with no fleet-wide reliability visibility and cannot tell whether the product works for anyone but us. | **Certain** (by design) | Medium — slower defect discovery, no regression signal on reliability | Accept and state it openly. Compensate with: a comprehensive on-device test matrix, a public issue template that asks for a bundle, and — if the PM wants it — a small opt-in beta cohort who share bundles manually. This is the price of the privacy posture and it should be a conscious decision (Open Question 1). |
| Binary size / dependency weight grows beyond what a lean OSS app should carry. | Medium | Low–Medium | OBS-25 (HTTP only, no gRPC/NIO); `opentelemetry-swift-core` has no Apple-platform transitive dependencies [1]; binary-size regression gate in OBS-25. |
| Apple changes `OSLogStore`, MetricKit (rebuilt for iOS 27 [30]), or background-execution policy under us. | Medium | Medium | The journal is ours and depends on none of them; MetricKit and `os_log` retrieval are both *enhancements* to the bundle, not load-bearing. |

---

## Hard constraints that limit the product

Stated loudly, per the brief's rules of engagement.

**HC-1 — HealthKit is unreadable on a locked device, and this will cause failures we cannot
fix.** HealthKit data is in the Data Protection class *Protected Unless Open*; access is
relinquished **10 minutes after the device locks** and is restored only when the user next
unlocks with passcode, Face ID or Touch ID [52][53]. A query on a locked device fails with
`HKError.errorDatabaseInaccessible` [54][55]. The only exception is an active `HKWorkoutSession`
[52]. Consequence: unattended, scheduled exports on a phone sitting on a bedside table will
fail, and the incumbent hits exactly this — its own error text says "Health data could not be
fully read. The device may have locked during the export" [20] and its help pages recommend
charging the device and using iPhone Mirroring as workarounds [19][20]. **We cannot engineer
around this.** The requirement is to detect it, name it precisely, and tell the user the truth.

**HC-2 — On iOS, we cannot read our own logs from a previous process.** `OSLogStore` supports
only `.currentProcessIdentifier` scope on iOS; `.system` scope and `OSLogStore.local()` fail
in the App Sandbox on macOS too [13][14][15]. You cannot read logs from a previous instance of
your own app, nor from your own app extensions [14][15]. Apple has the enhancement request
open (r. 57880434, FB12021495) and it has not shipped [15][56]. **This is the single constraint
that most shapes the design.** Without an app-owned durable journal, the product cannot answer
its own headline question.

**HC-3 — Debug-level logs are not available by default.** Debug entries are not persisted and
largely do not surface through `OSLogStore` unless `OSLogPreferences` sets `Enable`/`Persist`
to `Debug` in Info.plist [33]. "Turn on verbose logging and reproduce" needs deliberate
plumbing, and the related `Enable-Private-Data` key defeats `%{private}` redaction entirely
and must never ship in release.

**HC-4 — App Store 5.1.3 constrains where health-derived data may go.** No disclosure of
health/fitness-context data to third parties for data-mining purposes, and disclosure to any
third party requires express user permission *and* that the third party also provides a health
or fitness service to the user; PHI may not be stored in iCloud [46][47][48]. This is the
formal basis for OBS-27 and OBS-33.

**HC-5 — Background wake budget is scarce and rate-limited.** HealthKit notifies at most once
per the frequency registered at `enableBackgroundDelivery`; watchOS allows roughly four
background updates an hour and only with an active complication; failing to call the observer
completion handler triggers exponential backoff and **HealthKit stops delivering entirely
after three failures** [43]. Observer queries must be registered in `didFinishLaunching`
[42][43]. Background delivery is explicitly not real-time streaming and the system may batch
or delay based on battery and device state [57]. Telemetry gets whatever is left over, which
is approximately nothing.

**HC-6 — OTel Swift's metrics and logs are not stable contracts.** Metrics are "implemented
using an outdated spec... will change"; logs are "beta quality" [3][4]. We may not treat them
as a stable dependency in v1.

**HC-7 — OTLP/gRPC is not shippable here.** grpc-swift plus the SwiftNIO family is
unacceptable dependency and compile-time weight for a lean app [11][12], and is unsuitable on
watchOS. We are therefore obliged to use OTLP/HTTP, which the SDK's own README still marks
experimental [4]. Accepted trade; see OBS-25.

**HC-8 — Stable HTTP semantic conventions are incompatible with our privacy posture.**
`server.address` is required by stable HTTP span semconv [34] and is precisely the field that
can identify a person's clinic. We deliberately omit it and therefore cannot claim HTTP
semconv conformance, and cannot use the SDK's automatic `URLSession` instrumentation. Any
consumer of our OTLP output must be told this.

**HC-9 — We will have no aggregate view of our own reliability.** A direct consequence of
OBS-27. The project cannot compute a fleet-wide export success rate, cannot detect a
regression that only manifests on one device model, and cannot A/B a reliability fix. All
SLOs are per-install. This is a genuine capability loss and it should be an explicit,
recorded decision rather than an accident.

**HC-10 — `swift-log` is foreclosed in app targets, which limits code sharing.** OBS-29 means
that if we later build a Linux-capable shared core package, it will need its own logging
abstraction, and the two will not be unified. Accepted; revisit if a companion server enters
scope.

---

## Open questions for the PM

1. **Do we accept HC-9 — permanently zero fleet-wide reliability visibility?** I recommend
   yes, and I recommend recording it as an ADR so it is a decision rather than a discovery.
   But it means our only reliability signal is what users volunteer, and the PM owns that
   trade-off, not me.
2. **Is OBS-27 (no maintainer telemetry) accepted, or do you want the constrained OBS-28
   version behind a flag?** My recommendation is Won't, permanently, as an automatic channel.
   If you want optionality, decide now — OBS-28 requires a physically separate pipeline, and
   retrofitting that later is expensive.
3. **What is the minimum OS baseline?** This is load-bearing for me and I cannot answer it
   alone. `os.Logger` needs iOS 14; `OSLogStore` needs iOS 15 for entitlement-free access
   [16]; Swift 6.3 strict concurrency is far more pleasant on recent SDKs; and MetricKit was
   rebuilt for iOS 27 with a Swift-first API that OTel Swift has not adopted [30]. A modern
   baseline (iOS 18+ or 26+) simplifies several of my requirements. A conservative one
   (iOS 15/16) does not break anything but costs effort.
4. **Is user-collector OTLP export (OBS-23) v1 or v1.1?** It is the most OTel-shaped feature
   and the most attractive to the self-hoster audience, but it is also the only feature in my
   scope that introduces egress. If v1 must be small, I would ship the journal, history and
   bundle in v1 and OTLP export in v1.1 — but that means v1 does not visibly deliver the
   owner's stated OpenTelemetry ask, and that expectation needs managing with the owner
   directly.
5. **Do we ship a companion server or Grafana-side component?** If yes, `swift-log` +
   `swift-otel` become the correct choice *in that component* [24][25], my cardinality
   budgets change, and the "where does the trace terminate" answer changes because we would
   own both ends. If no, OBS-29 and OBS-16 stand as written.
6. **Notification permission timing.** Silent-failure escalation (OBS-12) is much weaker
   without notifications. Ask at onboarding (friction, before the user sees value) or on
   first failure (late, and possibly the only chance)? I lean toward asking after the first
   *successful* export, when the value is established — but this is a product call.
7. **Localisation scope for the error catalogue (OBS-05).** Every error class needs a cause
   and a remediation sentence in every shipped locale. How many locales in v1? This is a
   direct, non-trivial cost on my most important requirement.
8. **Does the security engineer's veto extend to `traceparent` egress at all?** I want to
   keep it as per-destination opt-in (OBS-16) because it is the one thing OTel does here that
   nothing else can. If the veto is absolute, the user-collector feature loses most of its
   distributed-tracing value and becomes metrics-and-spans-in-isolation — still useful, but
   the pitch changes and OBS-23 should be re-scoped accordingly.
9. **Where does the "150+ metrics" surface interact with my cardinality budget?** If the PM
   wants per-health-type metrics visible by default in the user's collector, OBS-18's default
   budget has to rise and I need to know before Stage 2.

---

## Sources

1. `opentelemetry-swift-core` `Package.swift` — platform declarations and dependencies. https://github.com/open-telemetry/opentelemetry-swift-core/blob/main/Package.swift
2. `open-telemetry/opentelemetry-swift-core` README. https://github.com/open-telemetry/opentelemetry-swift-core/blob/main/README.md
3. OpenTelemetry Swift documentation — status and releases (Traces Stable, Metrics Development, Logs Development). https://opentelemetry.io/docs/languages/swift/
4. `open-telemetry/opentelemetry-swift` README — "Current status": Tracing and Baggage stable, Logs beta quality, Metrics on an outdated spec. https://github.com/open-telemetry/opentelemetry-swift?tab=readme-ov-file
5. DataDog/dd-sdk-ios PR #2614 — upgrade OTel API to 2.3.0 and switch to `opentelemetry-swift-core`. https://github.com/DataDog/dd-sdk-ios/pull/2614
6. OpenObserve — "OpenTelemetry for Swift: iOS & Server Tracing" (no runtime agent; env-var configuration not implemented; OTLP/HTTP marked experimental). https://openobserve.ai/opentelemetry/swift/
7. `aws-observability/aws-otel-swift` `Package.swift` — a vendor SDK built on `opentelemetry-swift-core`. https://github.com/aws-observability/aws-otel-swift/blob/main/Package.swift
8. OpenTelemetry community `workstreams.yml` — Swift SDK SIG registration, weekly Thursday 09:00 PT meeting, `#otel-swift` Slack. https://github.com/open-telemetry/community/blob/main/workstreams.yml
9. opentelemetry-swift issue #990 — "Understanding iOS Instrumentation current state" (gap analysis vs `opentelemetry-android`). https://github.com/open-telemetry/opentelemetry-swift/issues/990
10. opentelemetry-swift issue #595 — "Large number of unnecessary [transitive] dependencies". https://github.com/open-telemetry/opentelemetry-swift/issues/595
11. `open-telemetry/opentelemetry-swift` repository metadata (Apache-2.0 licence, star/issue counts) and issue #389 "Separate OTLP Exporter HTTP from gRPC". https://github.com/open-telemetry/opentelemetry-swift/issues/389
12. DataDog/dd-sdk-ios issue #1877 — transitive dependency list and the 33.6 MB → 37.5 MB binary-size measurement. https://github.com/DataDog/dd-sdk-ios/issues/1877
13. Apple Developer Forums thread 691093 — "Can I use OSLogStore to access logs from earlier runs?" (`.currentProcessIdentifier` is tied to the process ID; no solution on iOS). https://forums.developer.apple.com/forums/thread/691093
14. Michael Tsai — "OSLogStore on Monterey" (in the App Sandbox only `.currentProcessIdentifier` works; cannot read a previous instance of your own app). https://mjtsai.com/blog/2021/12/10/oslogstore-on-monterey/
15. Apple Developer Forums thread 744806 — "Can I access system logs from Swift?" (no solution for the requirement; r. 57880434). https://developer.apple.com/forums/thread/744806
16. Peter Steinberger — "Logging in Swift" (os_log privacy defaults; Apple's warning about the swift-log os_log backend; OSLogStore entitlement-free from iOS 15). https://steipete.me/posts/2020/logging-in-swift
17. Swift Forums — "State of the Logging (swift-log) package" (Apple-platform `Logger` cannot be redirected to other backends; no structured metadata field; you should not encapsulate the system logger on Apple platforms). https://forums.swift.org/t/state-of-the-logging-swift-log-package/50943
18. apple/swift-log PR #117 — README clarification of the os_log backend's drawbacks (always `%{public}@`, eager interpolation, loses privacy control). https://github.com/apple/swift-log/pull/117
19. HealthyApps Help Centre — Health Auto Export "Automations" (Activity Logs, run grouping, warnings vs errors, background-execution workarounds). https://help.healthyapps.dev/en/health-auto-export/automations
20. HealthyApps Help Centre — "Sync Apple Health Data to REST API" (Activity Log error strings including the device-locked case; App Event Logs diagnostic ZIP). https://help.healthyapps.dev/en/health-auto-export/automations/rest-api
21. Lybron/health-auto-export issue #21 — automatic export reports "Succeeded" but no data reaches Home Assistant. https://github.com/Lybron/health-auto-export/issues/21
22. `opentelemetry-swift` releases (2.5.1, Aug 2026; 2.5.0; 2.4.1 May 2026). https://github.com/open-telemetry/opentelemetry-swift/releases
23. `opentelemetry-swift-core` releases (2.5.1, 29 Aug 2026). https://github.com/open-telemetry/opentelemetry-swift-core/releases
24. `swift-otel/swift-otel` README and `Package.swift` (`platforms: [.macOS("13.0")]`; "does not provide an OTel instrumentation API, or general-purpose OTel SDK"). https://github.com/swift-otel/swift-otel
25. Swift Forums — "Swift OTel 1.0.0 Released" (scope statement; "for folks that prefer... the OTel APIs... `opentelemetry-swift` will be the right choice"). https://forums.swift.org/t/swift-otel-1-0-0-released/82439
26. Swift OTel 1.0.0 release notes (OTLP/HTTP+protobuf, OTLP/HTTP+json, OTLP/gRPC via gRPC Swift v2; package traits). https://github.com/swift-otel/swift-otel/releases/tag/1.0.0
27. Swift Forums — "Swift OTel: Proposed revised API for 1.0 release" ("telemetry from mobile device" use case described as riddled with concerns; transport abstraction declined for 1.0). https://forums.swift.org/t/swift-otel-proposed-revised-api-for-1-0-release/80214
28. OpenTelemetry Swift SIG meeting details via the community page (referenced from the repository README). https://github.com/open-telemetry/community#swift-sdk
29. OpenTelemetry blog — "CocoaPods Deprecation Notice for OpenTelemetry Swift", 20 July 2026 (SPM the only forward path; support ends 2 Dec 2026). https://opentelemetry.io/blog/2026/otel-swift-cocoapods-deprecation/
30. opentelemetry-swift issue #1123 — support for the MetricKit rewrite in iOS 27 (new `MetricManager` API; WWDC26 session 222). https://github.com/open-telemetry/opentelemetry-swift/issues/1123
31. opentelemetry-swift-core issue #23 and PR #25 — deployment-target alignment; watchOS 4 build confirmed. https://github.com/open-telemetry/opentelemetry-swift-core/issues/23
32. Apple — WWDC20 session 10168, "Explore logging in Swift" (`Logger`, subsystem/category, privacy annotations, logs archived by the OS for later retrieval, efficiency). https://developer.apple.com/videos/play/wwdc2020/10168/
33. Stack Overflow 73700466 — enabling debug logging through OSLog via `OSLogPreferences` (`Enable`/`Persist`/`Enable-Private-Data`); `NSPredicate` matching rather than `.filter`. https://stackoverflow.com/questions/73700466/enable-debug-logging-through-oslog
34. OpenTelemetry — Semantic conventions for HTTP spans (Stable; client span required/recommended attributes). https://opentelemetry.io/docs/specs/semconv/http/http-spans/
35. OpenTelemetry — Semantic conventions for messaging spans (Development; `OTEL_SEMCONV_STABILITY_OPT_IN`). https://opentelemetry.io/docs/specs/semconv/messaging/messaging-spans/
36. OpenTelemetry semantic-conventions registry — `messaging.system` well-known values (MQTT not among them). https://github.com/open-telemetry/semantic-conventions/blob/main/docs/registry/attributes/messaging.md
37. OpenTelemetry — Semantic conventions for mobile events (`device.app.lifecycle`, `ios.app.state`). https://opentelemetry.io/docs/specs/semconv/mobile/mobile-events/
38. OpenTelemetry — Semantic conventions for session (`session.id`, `session.previous_id`, both Opt-In / Development). https://opentelemetry.io/docs/specs/semconv/general/session
39. `opentelemetry-swift` Persistence Exporter README — exporter decorator for environments that cannot guarantee stable export, including across app termination and relaunch. https://github.com/open-telemetry/opentelemetry-swift/tree/main/Sources/Exporters/Persistence
40. opentelemetry-swift PR #280 — introduction of the persistence exporter decorators. https://github.com/open-telemetry/opentelemetry-swift/pull/280
41. Reference persistence setup storing under `.cachesDirectory` and gating export on network availability, with watchOS excluded from network monitoring. https://github.com/dream-horizon-org/pulse/blob/main/pulse-ios-otel/Sources/PulseKit/PersistenceUtils.swift
42. Apple — "Executing Observer Queries" (register observer queries in `didFinishLaunching`; call the completion handler). https://developer.apple.com/documentation/healthkit/executing-observer-queries
43. Apple — `enableBackgroundDelivery(for:frequency:withCompletion:)` (background-delivery entitlement; at most one notification per frequency period; ~four updates an hour on watchOS with an active complication; backoff and permanent stop after three failures). https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:)
44. Apple — Third-party SDK requirements (privacy manifests and signatures). https://developer.apple.com/support/third-party-SDK-requirements
45. Apple — TN3182: Adding privacy tracking keys to your privacy manifest (`NSPrivacyTracking`, `NSPrivacyTrackingDomains`). https://developer.apple.com/documentation/technotes/tn3182-adding-privacy-tracking-keys-to-your-privacy-manifest
46. Apple — App Review Guidelines, 5.1.3 Health and Health Research. https://developer.apple.com/app-store/review/guidelines/
47. Apple — HealthKit "Protecting user privacy" (no advertising use; no third-party disclosure without express permission, and then only to third parties who also provide a health or fitness service). https://developer.apple.com/documentation/healthkit/protecting-user-privacy
48. App Store Review Guidelines 5.1.3(i) and (ii) verbatim, including the iCloud prohibition on personal health information. https://developer.apple.com/app-store/review/guidelines/#health-and-health-research
49. W3C Trace Context — Privacy considerations (no PII in `traceparent`/`tracestate`; random trace IDs; correlatability risk; trust boundaries and restarts). https://www.w3.org/TR/trace-context/
50. W3C trace-context specification source, `spec/50-privacy.md`. https://github.com/w3c/trace-context/blob/main/spec/50-privacy.md
51. W3C trace-context specification source, `spec/51-security.md` (information exposure; `tracestate` should not reach external systems; denial-of-monitoring via forged sampled traces; test all header-sending code paths). https://github.com/w3c/trace-context/blob/main/spec/51-security.md
52. Apple Platform Security — "Protecting access to user's health data" (Data Protection class *Protected Unless Open*; access relinquished 10 minutes after lock; `HKWorkoutSession` exception). https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web
53. Apple — Configuring HealthKit access (purpose strings; per-type authorisation; revocable at any time). https://developer.apple.com/documentation/xcode/configuring-healthkit-access
54. Apple — `HKError.Code.errorDatabaseInaccessible` ("HealthKit data is unavailable because it's protected and the device is locked"). https://developer.apple.com/documentation/healthkit/hkerror/code/errordatabaseinaccessible
55. Apple — `HKError.Code.errorDatabaseInaccessible` discussion (queries fail while locked; saves are journalled and merged on unlock). https://developer.apple.com/documentation/healthkit/hkerror/code/errordatabaseinaccessible
56. Mike Piontek — "OSLogStore should be more flexible" (cannot access extension or prior-process logs; periodic polling as the only workaround, with battery and SSD cost; FB12021495). https://mikepiontek.com/journal/oslogstore-should-be-more-flexible.html
57. Background support for HealthKit in iOS — background delivery is not real-time streaming; the system may batch or delay based on battery and device state; keep background work lightweight. https://medium.com/@rajveer.kaur.k19/background-support-for-healthkit-in-ios-aaa0c05fb6e3
