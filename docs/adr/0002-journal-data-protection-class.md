# ADR-0002 — Split Data Protection classes: journal Class C, payloads Class B

- **Status:** Accepted
- **Date:** 2026-09-03
- **Deciders:** Coordinating PM (Stage 2 SR-F-05)
- **Supersedes:** the Class-B-for-the-whole-database stance recorded as ADR-0005 in
  `docs/02-design/01-system-architecture.md` (that ADR file was never written; this one is
  the record)
- **Consulted:** `docs/02-design/05-observability-design.md` Q10 / ADR-OBS-03,
  `docs/02-design/reviews/01-adversarial-review.md` SR-F-05,
  Apple Platform Security *Data protection classes*

## Context

R-20 requires a durable journal of every run, including background wakes. The most common
wake condition is a locked device (C-02: HealthKit Protected Unless Open, ~10 minutes after
lock). A-1 adds `blocked_device_locked` so that refusal is recorded honestly rather than as
`failed`.

The architecture design opened the SQLite file with
`SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN` (Class B). Apple's Class B rule is: a
*closed* file is inaccessible while the device is locked. A cold background launch therefore
cannot open a Class B database.

That makes A-1 self-defeating: we cannot write "the device was locked" into a file we cannot
open because the device is locked. R-20 and R-22 fail for the same reason.

## Decision

Split by content:

| Data | Class | Flag |
|---|---|---|
| State, cursor, journal, ledger | **C** — Complete Until First User Authentication | `SQLITE_OPEN_FILEPROTECTION_COMPLETEUNTILFIRSTUSERAUTHENTICATION` |
| Payload blobs (sample values) | **B** — Complete Unless Open | `SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN` |

The journal holds metric names and counts, not sample values. Payload blobs are written
during a wake, not opened cold after lock.

The first-party SQLite wrapper sets the flag at open (this is one reason GRDB was not
chosen: the flag is a first-class open parameter, not a configuration hook).

## Consequences

- A wake after first unlock of the boot, device currently locked, can open the journal and
  record `blocked_device_locked`.
- A wake **before first unlock after reboot** still cannot. That window is accepted and
  documented; it is far rarer than the locked-but-previously-unlocked case.
- R-83's `StoreLocked` injector asserts a journal row exists.
- A one-hour device confirmation still runs at M2; it is confirmation, not the decision
  procedure.
- Payload files remain Class B. If a future design needs to *read* payloads while locked,
  that is a new ADR.

## Sources

- <https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web>
- Apple developer documentation: Protected Unless Open — "A closed file is inaccessible
  when the device is locked."
