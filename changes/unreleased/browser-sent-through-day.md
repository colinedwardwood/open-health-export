The data browser now reports what the export actually emitted for a type, read back from
the emitted index the run wrote, instead of a placeholder tied to selection (R-69). A type
that is selected but never sent shows no destination at all, because selection is not
evidence of delivery.

The emitted index records days, so the copy says data through a day has been sent rather
than naming a send time we do not have. A parity test runs a real export and asserts the
browser's claim matches the index, and that a type never exported claims nothing.
