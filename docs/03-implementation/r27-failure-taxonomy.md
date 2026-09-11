# R-27 monitoring signal and failure taxonomy

Schema version: `ohe.status/1` (`schema_version = 1`).

The local-file destination writes `status.json` atomically beside its NDJSON
batches after every run, including `successNothingDue` and failures. The file
contains run state, counts and freshness only; it contains no health values.

Stable outcomes and recommended actions:

- `success`, `successNothingDue`: no alert.
- `partial`: inspect `error_class`; alert only if repeated past the destination
  threshold.
- `unknownAck`: delivery is not confirmed. Investigate if sustained for 24
  hours; do not count it as success.
- `failed`, `localNetworkDenied`: alert when `age_seconds` exceeds
  `overdue_threshold_s`; the destination or local-network permission needs
  attention.
- `blockedDeviceLocked`: do not page. Health data was unavailable while the
  phone was locked; a later foreground run can recover.
- `abandonedNoBudget`, `cancelledBySystem`: do not page on one occurrence.
  iOS ended or did not budget the run.

Attribution is `execution` for foreground, manual, Shortcut, widget and launch
runs. It is `scheduling` for observer and background-task triggers. Current
records use `attribution_confidence = evidenced`.

Example shell check for a user-owned local folder:

```sh
jq -e '
  (.age_seconds // 0) <= (.overdue_threshold_s // 172800)
  and .outcome != "unknownAck"
' status.json
```

Until R-71 ratifies a threshold, both threshold fields are absent. Consumers
must choose their own threshold rather than reading a missing field as zero.
