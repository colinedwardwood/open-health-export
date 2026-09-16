---
category: fixed
---

iPad UI cases now expect "this iPad" in the empty data-flow line, matching the
running device instead of a hardcoded iPhone string. The iPad-only exporter
notice, empty history rows and destination refresh control use Dynamic Type
body text, and the diagnostic JSON preview is one wrapping block of black on
white so a lone brace cannot fail contrast. Keyboard queries use the first
match so a missing keyboard is a no-op rather than a snapshot error.
