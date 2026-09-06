The iOS harness now exposes the fixed "Where your data goes" status surface
and an egress-ledger view. Status is read from the same App Group snapshots as
the widget. Opening the ledger verifies its SHA-256 chain before showing the
latest 50 attempt/outcome rows; a broken sequence renders an explicit warning.
Rows contain destination, outcome, counts and bytes, never health values.
