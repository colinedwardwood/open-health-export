Security advisories are now verified with Ed25519 against two public keys compiled
into the app; the private keys are held offline and signing happens only in the
separate `advisory-sign` tool. A feed whose sequence number jumps implausibly far is
refused, so one bad feed cannot silence later advisories (#65).
