Wake attribution copy moved onto `AttributionKind`, where the classification lives, and is
now pinned by a test. R-22 is only met if a person can tell the two failures apart, so a
window iOS never woke us for reads "Nothing ran, so nothing failed to send" while a run
that woke on time and failed reads "This one is ours" (RK-4).
