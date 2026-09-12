# HIPAA context and covered-entity prohibition

Open Health Exporter is a consumer-controlled tool. A user installs it, selects data from their
own Health store, and directs that data to a destination they control. The project does not
operate a Health-data receiver for users and is not claiming to be a HIPAA covered entity or
business associate.

HIPAA status is contextual; it cannot be established or avoided by a product label. In
particular, this repository does not claim that every user, destination, deployment, or
downstream use is outside HIPAA. An organization using exported data must make its own
assessment.

## Prohibited arrangement

The project and its maintainers must not contract with, provide the app to, or operate it for a
HIPAA covered entity (or its business associate) to perform that entity's covered functions
without fresh, fact-specific legal review completed before the arrangement is agreed, announced,
piloted, or deployed.

That review must determine at least:

- the parties' covered-entity and business-associate roles;
- whether the project would create, receive, maintain, or transmit protected health information
  on behalf of another party;
- required agreements, safeguards, incident duties, retention, deletion, and audit controls;
- whether project-operated infrastructure, support access, or telemetry changes the data flow;
  and
- what product, privacy, security, support, and contractual changes are required.

No such review or arrangement is recorded in this repository. This document does not fabricate
legal approval and does not authorize one.

## Change control

A proposal involving a provider, plan, clearinghouse, employer health program, care-delivery
workflow, managed deployment, hosted receiver, or access by project personnel is a stop
condition. Record the legal review and update `PRIVACY.md`,
`compliance/egress-inventory.json`, `CYBERSECURITY.md`, and `SECURITY.md` before work resumes.
