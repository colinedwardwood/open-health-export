# Provenance

R-108 is three distinct claims. We can make two.

| Claim | Can we? | What backs it |
|---|---|---|
| **Auditable source** — the exact source of any released version is public and identifiable | **Yes** | Signed annotated tag; `source-<tag>.tar.gz` with a published SHA-256; `BUILDINFO` recording the exact commit |
| **Verifiable provenance** — this artifact was built from that source, by that workflow, on that runner | **Yes**, for artifacts *we* build | GitHub artifact attestations on a public repository. Verify a published artifact with `gh attestation verify --repo colinedwardwood/open-health-export --deny-self-hosted-runners <file>` |
| **Reproducible binary** — an independent party rebuilds the App Store binary bit-for-bit and it matches | **No, and we say why** | Apple re-signs and FairPlay-encrypts App Store binaries; what a user downloads is not what we uploaded |

Two further precisions:

- **R-84 is about export output, not build output.** Byte-determinism of the data we emit given
  identical input is a testable product property. It says nothing about whether the compiler is
  deterministic.
- We have not verified that Swift compilation is bit-reproducible, and must not assume it.

Until the first GitHub release exists, auditable source is the git history on `main`. Attestation
commands apply to artifacts attached to a release; they cannot be run against an unpublished
tree.

## The sentence we use everywhere

You can read the exact source of any released version, verify that every artifact we publish
came from that source, and build a working app yourself from a clean machine.
You cannot verify that the App Store binary matches, because Apple re-signs and encrypts
App Store binaries before delivering them. If bit-for-bit verification matters to you, build
from source — and that path is tested on every release precisely so that it works.

Build-from-source on a clean machine: `./scripts/build-from-source.sh` (see README).
