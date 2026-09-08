Seal the verified egress-ledger head after each terminal run with a permanent,
non-exportable Secure Enclave P-256 key on iPhone. The seal record is written
atomically after the journal transaction. Verification distinguishes an
invalid chain, a rewritten head, a missing seal, and a changed ledger identity.
Tests exercise the P-256 path with an ephemeral software key and wire a
deterministic seal through `ExportRun`. `DestructiveWipe` deletes every supplied
secret store and the old signing identity, resets durable state, then seals the
successor wipe-genesis entry with a fresh identity.
