Named-step HTTPS and Home Assistant destination tests: TLS, pin, 401, bearer
redaction in the HTTP preview, and entity GET attribute readback. HTTPS now
has the same indivisible preview, canary, TLS identity pin, real-path test, and
enable transition as local-file and companion destinations; a failed test
cannot produce a verified sink. The iOS destination editor now persists its
single-host allowlist and passing report, stores an optional bearer only in the
device keychain, shows the observed TLS/SPKI identity, pins every later send,
and ledgers explicit plain-HTTP opt-in before allowing export. Companion
canary uses the loopback broker. The iOS companion export now uses that
protocol canary as its `DestinationSetup` gate, stores only the passing report
and peer identifiers, and resumes without re-emitting trust events. Forgetting
the pairing marks a blocked, unacknowledged destination change. Catalogue adds
resting heart rate, VO2 max,
and blood glucose; mappings omit classes unless the catalogue names a real HA
class. Ledger-head tests use portable `HashLedgerSeal`; the device integration
is recorded separately. The iOS harness preview/share control exists only
after full-content review.
