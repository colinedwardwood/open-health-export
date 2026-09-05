### Companion pairing material (R-33)

`PairingSecret` is 32 bytes of PSK with injected randomness (deterministic in tests), no
`Codable`, no raw-bytes property, and a redacted `description` / `debugDescription`. The one way
to reach the key is `withKeyBytes`, which `CompanionPSK.preSharedKey(from:identity:)` in
`SinkCompanion` uses to build the TLS 1.3 PSK — that target is the only one depending on both
`CompanionWire` and `NetEgress`, which is what keeps key material out of everything else.

The QR payload is newline-delimited text (`ohe.pair/1`, Mac installation ID, base64url secret,
Bonjour service name), deliberately not a URL so no URL parser sits in the trust path. Parsing
fails closed on version, shape, field length, base64url alphabet, and secret length.

The confirmation string the user compares across both screens is SHA-256 over a domain tag, the
secret, and both installation IDs length-prefixed and ordered by UTF-8 bytes, so each side
computes the same value. Eight Crockford base32 glyphs (no I/L/O/U), formatted `XXXX-XXXX`, from
a bias-free 5-bit mask. Two golden codes are pinned so the derivation cannot drift silently.

Not done: keychain storage, QR rendering or scanning, and the pairing state machine's UI.
`PairingSecret`'s `Equatable` is the synthesized comparison — fine for round-trip assertions, to
be replaced if it is ever compared against attacker-influenced input.
