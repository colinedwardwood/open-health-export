# open-health-exporter (Swift 6.3.3, Xcode 26.6; FSL-1.1-ALv2, source-available; health-data tooling)

## Commands (repo root). This is a subset of CI, see "CI beyond this list"
- Test all: `swift test` (full pass needs zlib + mosquitto installed; `MosquittoExternalBrokerTests` also needs `OHE_MQTT_BROKER`)
- One suite/test: `swift test --filter <Suite or testName>` (tests use Swift Testing; filter is a regex on `Suite/test`)
- Linux-core build: `swift build --target CoreDomain && swift build --target CorrectnessEngine`
- Spec/freeze + import policy: `swift run policycheck` (run after any `spec/` edit)
- NFR mapping: `python3 qa/validate-nfr-mapping.py` (after editing `qa/nfr-mapping.json`)
- Xcode project is generated and gitignored: `xcodegen generate` or `scripts/generate-project.sh`
- iOS/Xcode builds and UI tests are slow, macOS-only: see `.github/workflows/macos-build.yml`, `scripts/ios-package-tests.sh`. Only on request.
- No lint/format command; CI runs `reuse lint` (SPDX headers on new files).

## CI beyond this list (see `.github/workflows/`)
pipelinecheck, exportruncheck, wirefuzz, corpus reproducibility, release-symbol check, coverage, r84 determinism, gitleaks.
NEVER run `scripts/mutation-check.py` locally: it rewrites source files.

## Layout
- `Sources/` Swift package targets (Linux-core; HealthKit only in `Sources/HealthKitSource`)
- `Apps/` iOS app, widget, macOS companion; `Tools/` CLI executables (policycheck, receiver, ...)
- `Tests/ExportCoreTests`, `Tests/HealthKitSourceTests`; `spec/v1.0.0/` wire schema + fixtures
- `scripts/` CI helpers; `qa/` evidence/baselines; `compliance/` egress inventory

## Rules that cause CI failures
- Every commit needs DCO sign-off: `git commit -s`.
- `spec/` is frozen-by-policy and CODEOWNER-protected. Never edit a released spec version in place: additive (A-class) changes need a
  MINOR `x-ohe-specVersion` bump, breaking (B-class) changes fail CI (`spec/v1.0.0/README.md`). `spec/v1.0.0/FROZEN` is absent today,
  so confirm any v1.0.0 edit with the owner and run `swift run policycheck`.
- Security-sensitive paths need mandatory review. The authority is `CODEOWNERS` and `.github/workflows/security-sensitive-diff.yml`
  (path list + egress regex: URL/socket/Keychain/telemetry/NW*/SecItem...). Check both before touching networking, redaction, trust,
  entitlements, workflows or `Tools/policycheck`. Keep such edits minimal and call them out.
- No real health data anywhere; no new runtime dependency without an ADR + Linux build check.
- User-visible changes get a fragment in `changes/unreleased/` (CONTRIBUTING; not CI-enforced). 445 exist: `ls` only, copy one's style.

## Workflow
- Run the `simplify` skill on every PR's diff before opening it, and again after substantive review changes. Apply its fixes in the PR. It covers quality only; run `/code-review` separately for bugs.

## Docs (47 files; don't grep the whole `docs/` tree)
- No docs index; the map is the table in `README.md`. Start: `docs/01-prd/PRD.md`, `docs/02-design/00-system-design.md`,
  `docs/02-design/03-wire-format-spec.md`, `docs/03-implementation/final-scope-audit.md`.
- `CONTINUITY.md` is the owner-succession policy, not a task log. Read only for release, signing or incident questions.
- Rules: `CONTRIBUTING.md`, `GOVERNANCE.md`, `SECURITY.md`.

## Context hygiene
`build/` and `.build/` (4 GB, generated) are denied in settings. `.claude/worktrees/` is a live worktree: don't search it. Scope `rg` to `Sources/` or `Tests/`.
