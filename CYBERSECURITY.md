# Cybersecurity policy

This policy records the project's secure-development and vulnerability-handling practices.
It is intended to provide the controls expected of an open-source software steward under
Article 24 of the EU Cyber Resilience Act (CRA), whether or not that classification ultimately applies.
It is not a claim of CRA compliance, conformity assessment, certification, CE marking, or legal
review.

## Scope and ownership

The policy covers source, build and release infrastructure, the iOS exporter, status widget,
Mac companion (planned for 1.1; iPhone only in 1.0), reference receiver, wire format, and
published security advisories. The
maintainer named in `MAINTAINERS.md` owns this policy. The project currently has one maintainer
and no deputy; `SECURITY.md` states the resulting response limitation truthfully.

The policy is reviewed for every release and after a material vulnerability, severe
development-infrastructure incident, new dependency, new network flow, or change in the entity,
funding, distribution, or support model.

## Secure development

- Keep HealthKit behind its adapter and network operations behind `NetEgress`; `policycheck`
  rejects direct network APIs elsewhere.
- Default destinations to no selected Health types. Require destination confirmation before
  export, minimize permissions, and keep insecure local-network exceptions explicit. An HTTPS
  or MQTT destination whose certificate is not publicly trusted receives nothing until you
  compare its fingerprint and confirm it, after which the app pins that certificate; without a
  pin, ordinary system trust is required. The Mac companion channel is authenticated with a
  32-byte pre-shared key from the pairing code (TLS-PSK), not a client certificate.
- Maintain the egress inventory in `compliance/egress-inventory.json`; reconcile it with source,
  privacy manifests, and privacy-label assessment on every release.
- Accept no third-party runtime package without review. Track system libraries and licences,
  and keep build-from-source instructions (`scripts/build-from-source.sh`).
- Release provenance attestations and an SBOM are intended release artifacts (see
  `PROVENANCE.md`). No workflow in this repository produces them yet; do not treat them as
  existing until the first release records them.
- Use synthetic fixtures only. Keep secrets and real Health values out of source, issues, CI
  logs, diagnostics, and release artifacts.
- Run tests, `policycheck`, secret scanning, dependency review, and release validation before a
  release. Security updates are available on the same terms as other releases and are never
  gated by payment or sponsorship.

## Vulnerability handling

Report vulnerabilities privately as described in `SECURITY.md`. The project encourages
good-faith voluntary reporting and coordinated disclosure. Reports are triaged for affected
versions, exploitability, Health-data exposure, credential exposure, and impact to build or
release integrity. The maintainer contains the issue, preserves only necessary evidence,
develops and tests a fix, and publishes an advisory when safe through GitHub security
advisories and release notes. Users who have turned on the optional, off-by-default in-app
feed (Ed25519-signed, two public keys compiled into the app, display-only) also see it there
(`docs/03-implementation/advisory-signing.md`). The feed is not hosted yet (#67), so until it is
no advisory can reach the app.

There is no bug bounty and no promise of payment. Response targets are not staffed service-level
agreements. Good-faith research that avoids privacy violations, service disruption, persistence,
and access beyond what is needed to demonstrate the issue will not be pursued by the project
merely for reporting the vulnerability.

## Incident and regulatory assessment

For an actively exploited vulnerability or a severe incident affecting development
infrastructure, the maintainer will:

1. contain the event and protect users before expanding investigation;
2. determine affected versions and whether Health data, credentials, signing material, source,
   builds, or distribution channels were exposed;
3. rotate credentials and keys, invalidate compromised artifacts, and publish remediation;
4. assess notification duties under the CRA, FTC Health Breach Notification Rule, and other
   applicable law, including whether a CSIRT, ENISA reporting platform, authority, or affected
   users must be notified; and
5. record decisions, evidence, timelines, corrective actions, and policy changes without copying
   Health values into the incident record.

The project has not recorded a legal determination of its CRA classification or reporting
schedule. Those questions require fresh legal review before assuming a statutory role or filing
a regulatory report. Nothing here substitutes for that review or fabricates one.

## Cooperation and records

The project will cooperate with a competent market-surveillance authority when legally
required, provide available technical information, and remediate substantiated deficiencies.
Security reports, incident records, release evidence, dependency records, and policy reviews are
retained only as needed for security, governance, and applicable obligations, with personal and
Health information minimized.
