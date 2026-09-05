# Stage 3 kickoff

**Opened:** 2026-09-03 after Stage 2 approval.

M0 first: R-70/R-71/R-73 harnesses. R-71 diary can start on-device before the harness exists.

Wedge (M1–M6): engine, journal, watchdog, local-file sink. MQTT, companion, HACS after M6.

First commit in this repo: Linux-buildable L0–L4 targets, `RunOutcome.derive`, thin SQLite
wrapper, import policy check, no HealthKit in core.

Now in tree: `ExportRun`, `LocalFileSink`, `HealthKitSampleSource` (Darwin-only; conversion
inside the query callback), `HealthKitThroughput.measure` for R-70. iOS M0 harness:
`./scripts/generate-project.sh` then open `OpenHealthExporter.xcodeproj`. Run R-70 on REF-B or
the XR (simulator stores are often empty). Local-file payloads are `ohe.wire/1` NDJSON
(header / records / footer). HTTPS POST of that file is in tree (`HTTPSSink` / `NetEgress`). R-31 verification core:
`DestinationSetup` + `VerifiedDestination` (export path no longer takes a raw sink). First-party
MQTT 3.1.1 publish-only is a separate `SinkMQTT` product (not `ExportCore`). Companion frames
and `CompanionSink` are in `ExportCore`.

Local-network egress: `NetEgress.ByteStream` is the sink-facing port and `NWByteStream` is the
package's only `NWConnection` — MQTT and the companion both ride it through pipe adapters. TLS
pins are enforced inside the handshake verify block (zero application bytes on mismatch), with
peer SPKI from `SPKIDigest` over the leaf certificate DER. The companion side dials a Bonjour
`_ohx-recv._tcp` name with a TLS 1.3 PSK; discovery is not authorization, only an exact match on
the paired name is dialable. Pairing material (`PairingSecret`, QR payload, Crockford
confirmation code) is in `CompanionWire`, and `CompanionPSK` in `SinkCompanion` is the only
bridge from a scanned secret to handshake material. Trust changes now leave `DestinationSetup`
as drained `TrustEvent`s mapped to prose-free `UserNotice`s (R-40/R-41).

`wirefuzz` fuzzes the companion and MQTT decoders on Linux in CI (three seeds, one
time-derived). It found and we fixed two non-canonical acceptances in the companion decoder;
decoded frames now re-encode byte-for-byte, which the protocol's digest de-duplication depends
on.

The Mac companion app is in `Apps/Companion-macOS`: folder picker, iCloud warning, pairing
QR plus selectable payload, receive window. After the phone's HELLO the Mac shows the same
SAS the phone computed from the QR. The iOS harness pastes that payload, shows the SAS, and
can push one page over TLS 1.3 PSK to the exact Bonjour name captured at pairing. Pairing
survives a closed receive window: PSK in Keychain, names in a JSON sidecar with no secret.
The phone can scan the QR (VisionKit) or paste. MQTT has a Darwin loopback-TCP test: a test-only
`NWListener` broker plus `NWByteStream`, not a packaged mosquitto.

Error-class registry, HAE loss-gated encoder, MQTT retain-off, Keychain data-protection ACL (no
biometry), and `os.Logger` are in tree. Next: MQTTS against a real broker, and camera scan plus
SAS on a physical phone.
