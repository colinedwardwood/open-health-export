# Community device matrix

This is the QA-29 volunteer checklist. It is not a device farm and it does not
replace R-71 soak or R-87 maintainer hardware. Results live in
`results.csv` in this directory. Do not invent rows.

## Before you start

- Follow only the README build-from-source steps.
- Do not paste real HealthKit values, screenshots of Health, or diagnostic
  bundles that still contain hostnames into issues or this spreadsheet.
- Use demo export on a simulator or a clean device if you do not want to grant
  Health read access.

## Copy-paste run

1. Build the iOS harness (`./scripts/build-from-source.sh` or Xcode on a personal team).
2. Acknowledge the locked-device disclosure before any Health permission control.
3. Enable the local archive folder (R-25 canary) and confirm last success appears.
4. Run **Export demo dataset** (type `local-file`) or one local-file page if you
   granted Health read access.
5. Confirm the destination line, overdue copy (if you wait long enough or use the
   UI-test seed), and that the HAE sidecar line says correctness claims do not apply.
6. Optional: add the status widget and tap it; the app should open destination status.
7. Record one CSV row. `device_class` is one of `iphone`, `ipad`, `simulator`, `mac`.
   `outcome` is `pass`, `fail`, or `blocked`. Put a GitHub issue URL in `notes` on fail.

## v1 target

At least five recorded results across at least three device classes. That target
is empty until volunteers (or the maintainer on named hardware) append rows.
