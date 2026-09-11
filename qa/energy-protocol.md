# Energy protocol

QA-25 / R-78. This is a manual measurement recorded in the release issue. It is
not a CI gate. Tethered Instruments perturbs the measurement; untethered variance
is large. Battery impact is found in the field, not by turning this into a
pass/fail job.

## Once per release candidate

1. Named device (prefer REF-A when it exists). Record model, OS build, starting
   charge percentage, and whether Low Power Mode is off.
2. Network as the user would use it (not airplane mode). Do not leave a debugger
   attached for the timed window.
3. Workload: three local-archive export runs of the T1 generator stream (or the
   largest store you have that is not real production Health data in a bug
   report) spread over 24 hours, plus normal lock/unlock.
4. Capture Instruments energy on device if you can; otherwise record start/end
   charge and the journal's per-run wall times.
5. On Mac, `powermetrics` is optional and only for the companion receive window.
6. Paste numbers into the release issue: device, OS, start charge, end charge,
   run count, mean CPU wake notes. Do not use those numbers as a delivery
   promise. R-78's 12% full-backfill ceiling stays unproven until named-hardware
   evidence exists.

## Field follow-up

Xcode Organizer energy and MetricKit CPU/application-time from TestFlight, when
that cohort exists. A battery regression is a rollback decision, not a green CI
check.
