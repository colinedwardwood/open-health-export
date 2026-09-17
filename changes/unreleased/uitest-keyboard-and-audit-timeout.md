---
category: fixed
---

Diagnostic JSON stays in the accessibility tree, so hiding visible lines is no
longer reported as inaccessible text on iPhone. Keyboard helpers look at the
accessibility dump before any typed Keyboard query, because `waitForExistence`
on an empty `app.keyboards` query still fails hosted XCTest. Dismissal acts on
the resolved keyboard element rather than `app.keyboards.buttons`. The
paused-anchor banner is asserted after first-run Continue rather than under the
cover. An accessibility audit that times out (Xcode -56 or XCTFuture 1000) is
tried once more before the case fails. Typing into a field accepts hardware
keyboard focus (via KVC `hasKeyboardFocus`) when no software Keyboard row is
in the dump.
