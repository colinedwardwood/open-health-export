# R-33 encrypted-backup protocol

This protocol verifies R-33, SEC-30, and SEC-33. It must use a physical device
and a genuinely encrypted local backup. Never use a real credential, health
value, hostname, or production diagnostic line as a canary.

## Preconditions

- Record the release candidate, device model, iOS build, operator, and date in
  the release issue.
- Use three unique synthetic canaries: credential, queued payload, and log.
  Put their UTF-8 strings one per line in a temporary file outside the repo.
- Seed those exact synthetic strings through the app's development test surface.
  Confirm all three exist on-device before backing up.
- Ensure Finder's **Encrypt local backup** is enabled. Store neither the backup
  password nor the canary file in the repository or release issue.

## Encrypted local backup (each release)

1. Disconnect the debugger, lock and unlock the device once, and create a fresh
   encrypted Finder backup.
2. Verify in Finder that the latest backup is encrypted.
3. Using a locally trusted backup tool, decrypt/extract that backup into a new
   temporary directory. The scanner intentionally refuses a tree without
   `Manifest.db`; pointing it at opaque encrypted blobs is not evidence.
4. Run:

   ```sh
   python3 qa/encrypted-backup/scan_backup.py \
     --root /private/path/to/extracted-backup \
     --canary-file /private/path/to/canaries.txt
   ```

5. A pass is exit 0, `Manifest.db` present, every regular file and path scanned,
   and zero canary hits. Attach only the command's value-free summary and the
   backup artifact digest to the release issue.
6. Delete the extracted backup and canary file after recording the result.

The scanner examines raw file bytes, path names, and SQLite-readable text from
`Manifest.db`. A tool error, unreadable file, missing manifest, or canary hit is
a failure—not a waiver.

## Restore leg (each minor release)

1. Restore the encrypted backup to a second physical device.
2. Before entering any destination credential, confirm that no destination can
   send, no queued payload is present, and no seeded log line is present.
3. Confirm the SEC-64 disclosure that credentials do not migrate is shown before
   credential re-entry.
4. Record per-check `pass`, `fail`, or `blocked`, device/OS metadata, operator,
   date, and issue references. Do not record values from Health or any secret.

Neither this document nor a scanner pass claims that either physical leg has
been run.
