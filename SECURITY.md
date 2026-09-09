# Security

This project handles HealthKit data. Please report vulnerabilities privately to the address
listed on the GitHub Security Advisories tab for this repository.

There is currently one maintainer and no deputy. We will look at reports as soon as we can.
This file does not promise a response time.

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

