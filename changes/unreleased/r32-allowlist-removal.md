R-32: add a full HTTPS ExportRun acceptance harness proving that removing a
previously valid host from the current allowlist prevents source reads, DNS,
transport execution, and receiver traffic. The packet-capture exclusions are
limited explicitly to OS-initiated DNS, OCSP, CRL, and CT traffic.
