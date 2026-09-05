# ADR-0003 — First-party MQTT 3.1.1 publish-only client

- **Status:** Accepted
- **Date:** 2026-09-03
- **Deciders:** Project owner (O-2)
- **Supersedes:** nothing
- **Consulted:** `docs/02-design/04-security-design.md` (T-36, supply chain),
  `docs/02-design/reviews/01-adversarial-review.md` SR-F-12

## Context

D-04 admitted MQTT as v1's only non-Apple runtime dependency, originally costed as a library
integration (~3 EW). The security engineer recommended a first-party publish-only client so
that R-32's allowlist, R-31's pin-on-first-use, address-class re-check and trust anchors stay
on a single enforcement path. A third-party stack typically brings its own TLS and connection
establishment.

QoS 1 is the product default. Under MQTT 3.1.1, retransmission at the protocol layer is
required only when reconnecting with CleanSession=0. Connecting with CleanSession=1 and
republishing from the app's own durable queue is spec-conformant and needs no MQTT-level
session persistence.

## Decision

Hand-roll a **publish-only MQTT 3.1.1** client:

- Packets: CONNECT, CONNACK, PUBLISH, PUBACK, PINGREQ/PINGRESP, DISCONNECT
- CleanSession=1
- QoS 1 default, QoS 0 opt-in (separate unconfirmed clock; does not arm R-23/R-27)
- No subscribe, no websockets, no MQTT 5 property system, no broker-side session
- TLS is the same stack as HTTPS destinations (R-31/R-32/R-35)

Lives in `SinkMQTTPackage`, which never enters `ExportCore`'s resolution graph (R-80).

## Consequences

- Cost is unpriced relative to the 3 EW library figure. Record the actual EW at M0 against
  this ADR; if it exceeds ~5 EW, reopen.
- A future contributor who "improves" this into a general client is a regression. The
  constraint list above is the test.
- R-90's broker conformance tests are against this client, not against a vendor suite.
- R-50 already allows a transitively linked `swift-log` if we later reverse this ADR; first
  party makes that moot.
