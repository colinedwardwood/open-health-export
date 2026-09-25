iOS no longer crashes on launch or when testing or exporting to an HTTPS or Home
Assistant destination. Every HTTP request now uses the destination's own ephemeral
session and pin instead of a shared background session, and an export holds a
background-task assertion while it uploads (#27).
