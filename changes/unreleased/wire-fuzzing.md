### Fuzzing the wire decoders (R-84)

`wirefuzz` is a seeded, self-contained fuzzer over `CompanionFrame`, `CompanionMessage`,
`MQTTCodec`, `MQTTRemainingLength` and `NativeWire.countRecords`: random byte strings plus
bit-flipped, truncated, extended and length-corrupted mutations of valid frames. Every input
must end as a value, as "incomplete", or as a thrown error from a known error type — a trap is a
crash and therefore a CI failure. Every decoded companion message must re-encode to exactly the
bytes it arrived as. CI runs three seeds at 200k iterations, one of them time-derived, so the
corpus is not frozen to whatever the author happened to try.

It also drives a million pathological declared-length decodes in ~0.15s, which is the evidence
that no decoder sizes a buffer before validating a declared length against the real one; on
Linux it additionally fails if the resident set grows more than 64 MiB across that loop.

The fuzzer immediately found two byte-level defects in the companion decoder, both now fixed:

- a `reject` frame's `retryable` byte was read as "any non-zero means true", so 255 distinct
  wire frames decoded to one message. Only `0` and `1` are accepted now, and anything else
  throws `badBoolean`.
- length-prefixed strings were decoded with `String(bytes:encoding:)`, which goes through
  Foundation and silently strips a leading UTF-8 BOM, shrinking the frame on re-encode and
  making the result Foundation-version dependent. Strings now decode with
  `String(validating:as:)`, which preserves the bytes and still rejects invalid UTF-8.

Both mattered because the companion protocol de-duplicates on digests and idempotency keys: two
wire byte strings decoding to one message, or a re-encode that is not a faithful copy of what
the peer sent, undermines exactly that.
