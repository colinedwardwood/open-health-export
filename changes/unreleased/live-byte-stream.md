### One socket for MQTT and the companion

`NetEgress` gains `ByteStream` (open / send / receive / close / identity) plus `StreamEndpoint`,
which resolves host, port and TLS-or-not only from a URL that already passed the allowlist —
scheme defaults are 8883/1883 for MQTT and 443/80 for HTTP, and a port of 0 is refused.

`NWByteStream` is the one `NWConnection` in the package (Darwin only, `#if canImport(Network)`).
TLS pinning runs inside the handshake verify block, so a pin mismatch fails the connection
before an application byte is written, and it is reported as `pinMismatch` rather than a generic
transport error. Peer SPKI comes from `SPKIDigest` over the leaf certificate DER. Minimum TLS
1.2, optionally 1.3.

A refused or unroutable destination does not fail a `NWConnection` — it parks it in `.waiting`
and retries. The connect timeout now reports the waiting reason ("connection refused") instead
of a bare timeout, and `Options.failFastOnWaiting` gives the R-31 destination test an immediate
answer instead of a spinner.

`ByteStreamMQTTPipe` and `ByteStreamCompanionPipe` adapt it to the two sink protocols; both call
`open()` lazily, which is idempotent. `LoopbackByteStream` exercises the adapters without a
socket.

For the companion, `NWByteStream` can also dial a Bonjour service name with TLS 1.3 PSK from
pairing (no certificates, so no verify block and no trust store). `CompanionDiscovery` browses
`_ohx-recv._tcp`, but discovery is not authorization: only a service name exactly equal to the
one captured at pairing may be dialled.

`policycheck` now also denies `import Security` outside `NetEgress`, and denies `NWListener` /
`NWBrowser` anywhere under `Apps/` (R-34: the phone dials out, the Mac listens).

Not yet exercised against a live broker or a live companion. `TLSIdentity.notBefore` /
`notAfter` are still empty from the live path — certificate validity needs a DER date parse.
