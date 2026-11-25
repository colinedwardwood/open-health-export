<!--
SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
SPDX-License-Identifier: FSL-1.1-ALv2
-->

# ADR-0006 — Copy owned by Sources/ is a catalog key, resolved by the app

- **Status:** Accepted
- **Date:** 2026-11-25
- **Deciders:** Project owner
- **Supersedes:** nothing
- **Consulted:** issue #54, `Apps/Localizable.xcstrings`, ADR-0004 (no extra runtime packages)

## Context

Much of the live screens' copy (priming, status lines, run history, errors, About)
is produced in `Sources/`, which must keep building on Linux (`CoreDomain`,
`CorrectnessEngine`). `LocalizedStringResource` and Xcode-compiled module catalogs
are not available there, so that copy was plain `String`, shown verbatim, and never
localised or pseudo-localised.

## Decision

`Sources/` returns `LocalizedCopy` (in `CoreDomain`): the catalog key (English source
text in printf form, `%@` / `%lld`) plus its arguments. The app resolves it against the
one catalog, `Apps/Localizable.xcstrings`, with `Bundle.localizedString` and a locale
aware `String(format:)`. Counts use catalog plural variants; the `one` English form is
carried beside the key so Linux tests and logs read correctly. Fixed sentences held in
data (the error-class manifest, state labels) are resolved by their English text
through `localized(_:)`.

Entries Sources owns carry the catalog comment `Sources copy (LocalizedCopy)`. Gates:

- `LocalizedCopyCatalogTests` produces every such key from the real APIs and fails on
  a missing key, a stale tagged entry, or a plural without `one` and `other`.
- `policycheck` fails on a literal `LocalizedCopy` key absent from the catalog.

## Consequences

- No new dependency and no Apple-only API in Linux-core targets.
- Remaining plain-`String` copy in `Sources/` (data flow explainer, scheduling copy,
  wipe and unlock copy) migrates to `LocalizedCopy` incrementally; new copy must use it.
- Languages beyond English are #127.
