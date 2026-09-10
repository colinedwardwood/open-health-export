A nightly upstream canary divergence now opens a tracking issue, or comments on the open
one, carrying the expected and observed proof, the workflow run and the commit (QA-22).
The canary still fails; the issue is in addition to the red, not instead of it.

Issue titles no longer embed the diverging version. A title naming the version is a new
title every time upstream moves, so each release would have filed a fresh issue rather
than updating the one already tracking the drift.

`DRY_RUN=1` still prints what would be filed instead of filing it. This script's side
effect is public issues, so it needs to be runnable without producing them.
