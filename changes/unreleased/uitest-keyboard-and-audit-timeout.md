---
category: fixed
---

Diagnostic JSON stays in the accessibility tree, so hiding visible lines is no
longer reported as inaccessible text on iPhone. Keyboard helpers walk the
keyboards that actually exist instead of querying a first match that throws when
the query is empty, and an accessibility audit that times out on a hosted runner
is tried once more before the case fails.
