---
category: fixed
---

Diagnostic JSON stays in the accessibility tree, so hiding visible lines is no
longer reported as inaccessible text on iPhone. Keyboard helpers use
`waitForExistence` so an empty Keyboard query does not fail the test, and the
paused-anchor banner is asserted after first-run Continue rather than under the
cover. An accessibility audit that times out on a hosted runner is tried once
more before the case fails.
