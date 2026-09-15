Release validation now requires every iPhone/iPad UI shard and all T1/T2 volume
jobs by their exact check names. A single green matrix leg can no longer stand
in for the rest, and the release checklist's T0–T3 claim is bound to actual
fifty-million-record ExportRun evidence.

QA-22 upstream-canary evidence is also machine-readable. Validation rejects a
missing or older-than-48-hour run, and rejects a canary that has remained red
for more than 24 hours unless its generated open tracking issue links that run.
The report is retained with the other release evidence.
