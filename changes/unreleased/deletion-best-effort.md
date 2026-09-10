The iOS app now states that HealthKit deletion reporting is best-effort, that
there is no deletion callback, and that full reconciliation repairs missed
deletions. The matching no-callback reconciliation path is covered end to end.

HTTPS and MQTT verification now return and display the exact dry-run canary
payload beside the probed certificate identity before the user starts a Health
export.

Authorization changes are now observed on every eligible launch and wake even
when the local-file destination is disabled. Revocation purges emit a dedicated
user notice, and timed purge, delete-only, and restore reconciliation contracts
are explicit regression tests.

Policy checks now pin the host tzdata release separately on Darwin and Linux so
an SDK or runner update cannot silently change calendar-derived output.
