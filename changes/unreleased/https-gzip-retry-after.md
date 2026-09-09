Local-file and HTTPS accessibility: status and disclosure copy wrap instead of
clipping at AX5, browser rows hide decorative glyphs, and UI tests scroll farther
to reach type rows on the taller harness.

HTTPS POST bodies are gzip level 1 with `Content-Encoding: gzip`. Transient
failures honour `Retry-After` (delta-seconds or HTTP-date, capped at 24 h).
`URLSession` no longer follows redirects, so a 3xx cannot skip the allowlist.
