Every TLS connection without a pin now requires the system to trust the
certificate. Setting up a destination whose certificate is self-signed or from a
private CA shows its fingerprint and sends nothing, including the test and any
credentials, until you confirm it; the destination is then pinned to that
certificate (#66).
