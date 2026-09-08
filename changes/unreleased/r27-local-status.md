The local-file run path now writes a sorted, atomic `status.json` after every
outcome, including nothing-due and failures. `ohe.status/1` carries stable run
sequence, freshness and confirmed-ack timestamps, counts, trigger attribution,
error class and optional R-71 thresholds, but no health values. The published
failure taxonomy includes a `jq` alert example and does not invent a threshold
before R-71.
The iOS `Last successful export` App Intent returns one typed entity per
destination with label, success and confirmed-ack timestamps, age, state,
outcome, attribution, confidence and error class. It reads only App Group
snapshots and needs no network or collector.
