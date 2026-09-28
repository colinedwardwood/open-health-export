Exports now run through an `ExportService`: the automatic fan-out, full reconcile, backfill,
gap re-export, per-destination runs, queue expiry, recovery and wipe. Which destinations a
trigger runs, drain limits, low-power/thermal tuning, the scheduled-reconcile gate and
per-destination status outcomes are tested `AppServices` types; `HarnessExport` keeps forwarders (#42).
