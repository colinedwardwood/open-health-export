R-86 checkpoint encode/decode is pinned to committed OHEC goldens. Truncated,
empty, garbage, and forward-version fixtures fail closed instead of resetting
to a zero cursor.
