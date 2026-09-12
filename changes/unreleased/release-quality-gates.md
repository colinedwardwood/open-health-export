QA-31 / QA-32 / QA-33 / R-107 / R-108 / R-110: add fail-closed,
machine-readable release evidence validation, critical-module and patch
coverage thresholds, a last-20-nightly flake report, and release-artifact
sponsor-gating scans. Repository rules still must require the validation
workflow before a tag or release is published.

Release validation now also requires individually linked device, soak, canary,
energy, accessibility, performance, migration, flake, compliance, provenance,
and stranger-build evidence rather than accepting a non-empty evidence section.

The weekly T2 job now streams all fifty million pathological records through
both structural validation and bounded `ExportRun` processing while hashing
the same stream, with the 100 MiB RSS ceiling enforced at the full tier.
