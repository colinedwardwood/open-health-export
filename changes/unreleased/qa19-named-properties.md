Named P4/P5/P7/P13 tests and a QA-19 census of `p1`…`p16`. policycheck rejects a
`pull_request` workflow that also uses `runs-on: self-hosted`. Property tests stay
in-repo (ADR-0004) rather than adding a checker package.
