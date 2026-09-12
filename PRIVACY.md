# Privacy policy

Open Health Exporter is designed without accounts, advertising, analytics, crash reporting,
or a developer-operated Health-data service.

The project does not collect, sell, or share personal information. It does not send product
telemetry to the project.

This statement describes the software in this repository. It is not a claim about a destination
you configure, an operating-system service, a network provider, or software you modify.

## What leaves the device

The authoritative, machine-checked list is
[`compliance/egress-inventory.json`](compliance/egress-inventory.json). In summary:

- A Health export goes only to a local directory or HTTPS, MQTT, or Mac companion
  destination that you configure and control. Health destinations start with no selected types.
  Nothing is exported until you choose types and a date range and confirm the destination.
- OTLP is disabled by default. When enabled, it sends redacted export-run events to the
  observability endpoint you configured, plus bounded last-success and staleness gauges keyed
  only by opaque local destination IDs. That is user-directed operational telemetry, not
  telemetry received by this project, and it contains no Health values.
- Companion discovery uses Bonjour on the local network and transfer is limited to the paired
  companion.
- The only built-in Internet host is
  `https://advisories.openhealthexporter.org/advisories/v1.json`. At most once per 24 hours, on
  a user-visible foreground launch, the app may send an empty GET carrying only the app's coarse
  major.minor version in `User-Agent`. Security-advisory fetching can be turned off.

The advisory server and intervening networks necessarily see ordinary connection metadata,
including the source IP address and time. The request sends no Health data, account identifier,
device identifier, cookie, authorization value, or request body. Hosting must disable access
logging where the provider supports it and otherwise minimize retention. This repository cannot
prove a hosting provider's live configuration; that configuration must be checked before the
endpoint is operated or a release is submitted.

## Storage, deletion, and consent

Health reads, queued payloads, anchors, and export history remain on the user's devices until
sent to a chosen destination or deleted locally. The app-managed storage root is excluded from
device backup. A destination may retain what it receives according to the user's configuration;
the project cannot delete data from a receiver it does not operate.

You can stop future disclosure by disabling or removing destinations, deselecting Health types,
turning off advisory fetching, and revoking Health access in iOS Settings. Removing local app
data does not remove copies already delivered to a user-controlled destination.

## Apple privacy disclosures

The three committed `PrivacyInfo.xcprivacy` files declare no tracking, no tracking domains, and
no data collected by the developer. The repository records “Data Not Collected” only as a
source-level candidate for the App Privacy label: it is valid only if live advisory hosting does
not retain or expose transport metadata to the project. `policycheck` compares the manifests and
candidate assessment with the egress inventory.

This is an engineering assessment, not an App Store Connect declaration and not a representation
that one has been submitted or approved. Submission readiness is blocked until the built app,
Xcode privacy report, live advisory-host logging, and current App Store questions are verified.

## Changes

Adding an endpoint, SDK, destination, payload field, telemetry collector, or Apple privacy
declaration requires updating the inventory and this policy in the same change. A first-party
telemetry collector would invalidate the current no-collection posture and requires a new
privacy and legal analysis before release.
