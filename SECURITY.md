# Security

This project handles HealthKit data. Please report vulnerabilities privately to the address
listed on the GitHub Security Advisories tab for this repository.

There is currently one maintainer and no deputy. **Target** for an initial
acknowledgement of a private report is 14 days. That is a target, not a staffed SLA;
this file does not promise we will hit it.

Coordinated disclosure: we prefer to ship a fix before a public write-up. If we cannot
respond, you may disclose after 90 days from the report. Do not include HealthKit
sample values in either the private report or the public write-up.

Do not file security issues in the public tracker.

## Accidental health data or secrets (QA-06)

If real HealthKit data, credentials, or a private key lands in git, CI logs, artifacts,
or a GitHub issue:

1. Stop distributing the leak. Do not push further copies. Do not paste the payload into
   another ticket.
2. Rotate every credential that appeared (destination tokens, MQTT passwords, signing keys).
3. Open a private GitHub Security Advisory. Do not describe the health records in public.
4. Rewrite only with an explicit maintainer decision: history rewrite does not reach forks
   or local clones. Treat public commits as unrecoverable for privacy.
5. Record the incident date, systems touched, and rotation evidence in the advisory. Keep
   sample values out of that record.

Fixtures in `spec/` must stay synthetic. A missing `"synthetic": true` provenance header
fails `policycheck`.

## Security and compliance governance

The secure-development, vulnerability-handling, incident-assessment, and authority-cooperation
policy is in [`CYBERSECURITY.md`](CYBERSECURITY.md). It adopts CRA Article 24-style controls as
good practice; it does not claim a CRA classification, conformity assessment, certification, or
legal review.

The privacy policy is [`PRIVACY.md`](PRIVACY.md). Its claims are checked against the
authoritative [`compliance/egress-inventory.json`](compliance/egress-inventory.json), the
committed Apple privacy manifests, and the repository's privacy-label assessment.

The project is not a HIPAA covered entity and is not claiming business-associate status. Do not contract
with, provide the app to, or operate it for a covered entity to perform its covered functions
without fresh, fact-specific legal review. The explicit stop condition and required review scope
are in [`compliance/HIPAA-CONTEXT.md`](compliance/HIPAA-CONTEXT.md). No such legal review or
arrangement is recorded in this repository.

