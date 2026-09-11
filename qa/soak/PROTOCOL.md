# R-88 21-day soak protocol

This is a recording and validation skeleton, not evidence of a completed soak.
Run it on one physical device for at least 21 consecutive calendar days. Use an
upsert-capable destination; an HAE-profile destination should be excluded unless
its limitations are intentionally classified as explanation class 4.

## Start

1. Copy `diary.synthetic.json` and `result.synthetic.json` outside the repository.
2. Replace synthetic metadata with named device, exact OS/app builds, destination
   profile, operator, UTC start date, and a random run UUID.
3. Keep reconciliation worksheets private. They may contain only opaque metric/day
   cell IDs and counts—never values, sample identifiers, source app names,
   credentials, or destination hostnames.

## Daily diary

At approximately the same local time each day, append exactly one entry:

- local calendar date and UTC recording timestamp;
- whether the app remained installed and the destination remained configured;
- whether a successful check is visible;
- observed interruption flags (restart, update, offline period, queue gap);
- value-free issue/evidence references and notes.

Do not manufacture a missing day. A missing date or continuity break means a new
21-day window is required. Background wake timing is observational; manually
opening the app to force a success does not prove background delivery.

## Day 21 or later

1. Run the product's full reconciliation over the soak window.
2. Record comparison-cell totals and discrepancy totals in the private result.
3. Classify every explained discrepancy as exactly one of:
   `healthkit-no-callback-deletion`, `r71-platform-cap`,
   `queue-eviction-with-gap`, or `hae-profile-limitation`.
4. Any discrepancy not supported by one of those classes is unexplained and P1.
5. Sign the result as `pass` only when the diary is continuous, reconciliation was
   completed, and unexplained discrepancy count is zero.
6. Validate:

   ```sh
   python3 qa/soak/validate.py \
     --diary /private/path/diary.json \
     --result /private/path/result.json
   ```

Publish only the validator's value-free summary, sign-off, issue links, and
artifact digests. Do not commit completed device diaries or reconciliation files.
