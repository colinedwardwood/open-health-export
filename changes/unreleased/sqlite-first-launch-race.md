A first launch no longer shows "Failed to enforce queue expiry" or "Failed to load
local-file scope". The state store sets its busy timeout before anything else, runs
every schema change in one transaction, adds only the columns an older store lacks,
and the app opens one store per file and serialises its transactions (#25, #26).
