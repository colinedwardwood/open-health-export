Published copy is now gated against medical-claim language (R-113), and the canonical
disclaimer is required on the surfaces we actually ship (R-109).

The denylist would also fail the honest sentence that this is not a medical device, so
negation in the same window is discarded, and leftover hits — today, "diagnostic" as the
name of our observability bundle — must be listed in `compliance/allowlist.txt` with a
reason. Growth of that list is printed on every policycheck run.

`CONTINUITY.md` now states the App Store bus factor of one under individual enrolment
(R-106), and points at the stranger-test build and the licence as the mitigations.
