# Known issues and status

This is the one place to check whether a problem you see is already known. The app reports
nothing back to the project, so this page only lists what users and the owner have reported.
TODO-owner: publish this page at a stable web address and link it from the app's Support row
(the in-app link is not built yet). Until then it is the file in the repository.

Last reviewed: TODO-owner: date on each release and after each incident.

## How iOS behaves (not bugs)

- Health data is locked while the iPhone is locked. Automatic exports that run then wait and
  catch up after you unlock.
- iOS decides when background exports run. It can skip or delay them, for example in Low Power
  Mode or when you have not opened the app for days. Export now always works when the phone
  is unlocked.
- A deletion in Health may not be noticed: HealthKit gives the app no deletion callback.
- An upload cut off by suspension is sent again under the same idempotency key. A receiver that
  ignores that key may see it twice.

## Current known issues

| Affects | Symptom | Workaround | Status |
|---|---|---|---|
| (none recorded) | | | |

Add a row per issue: affected versions, symptom in the user's words, workaround, status, date.
Remove a row only when the fix has shipped and a version number is recorded.

## When an iOS update changes behaviour

If an iOS release or beta changes HealthKit access or background delivery, add a row the same
day with the iOS version, the symptom and "use Export now" as the workaround.

## Report something new

Use GitHub Issues for bugs; see `SUPPORT.md`. Do not paste Health values, tokens or private
hostnames. Security problems go to `SECURITY.md`.
