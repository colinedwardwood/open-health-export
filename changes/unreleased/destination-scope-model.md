Begin SEC-16 with a versioned, fail-closed per-destination export-scope model.
A destination without both explicitly selected metric types and a start date
cannot receive health records. Date ranges are start-inclusive/end-exclusive,
may remain open-ended for ongoing export, reject empty or reversed intervals,
and serialize deterministically as one atomic document.
