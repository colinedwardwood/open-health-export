Add an explicit R-84/QA-07 100-run byte-determinism gate for UTC and
fixed-offset fixtures. A dedicated script regenerates the committed T0 corpus
under a hostile locale and POSIX fixed-offset TZ, checks SHA-256 plus
pipelinecheck, and reuses policycheck's host tzdata pins. A fork-safe workflow
runs that script on the GitHub-hosted architectures that exist today: Linux
x86_64, Linux arm64, and macOS arm64. It does not claim Darwin x86_64.
