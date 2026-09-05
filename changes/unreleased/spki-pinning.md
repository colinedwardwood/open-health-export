### SPKI extraction for pinning

`SPKIDigest` walks an X.509 certificate's DER and returns the `SubjectPublicKeyInfo` element's
bytes, then hashes them with the first-party SHA-256. Pinning the key rather than the
certificate is what lets a renewal that keeps the same key keep the same pin; a test asserts a
new serial and validity leave the digest unchanged while changed key bits change it.

The walker is definite-length only and defensive by construction: indefinite lengths, length
fields over four bytes, and lengths exceeding the real buffer all throw, and lengths accumulate
in `UInt64` so a four-byte length cannot overflow `Int` on a 32-bit target. Bounds come from the
buffer extent, never from a length the input declared, so a header claiming two gigabytes throws
after six bytes without allocating. No `Security`, no `CryptoKit` — it builds and is tested on
Linux.

It decodes nothing inside the SPKI (no OIDs, no key parsing) and validates nothing else about
the certificate: no chain, no signature, no dates. Trailing bytes after the certificate are
ignored, since the caller hands us a leaf purely to pin a key.
