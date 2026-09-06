### Hash-chained egress ledger and wipe genesis

Every attempt and outcome is sealed into a SHA-256 chain over canonical fields,
including sequence, prior hash, destination, counts, bytes, outcome, detail,
and wall time. Verification detects edits, removals, and reordering. Delete-all
retains a successor genesis marker with the destroyed count and prior head.
Secure Enclave sealing of the chain head remains a device integration.
