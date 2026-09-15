The soak reconciliation gate now measures the duplicate rate, not only unexplained
loss. TA-06 asks for both, because zero loss bought by duplicating everything is
passing the wrong test, and the result schema had no field for it: a 21-day soak that
sent every record twice would have signed off clean. `reconciliation.duplicates` is
now mandatory and the rate is derived against `cellsCompared` rather than
self-reported, so the ceiling cannot be cleared by quoting a flattering percentage.
The validator grew a `--self-test` that proves the gate rejects an over-ceiling rate
and an omitted count, and `policycheck` runs it, so the validator that judges the
off-CI soak is itself checked on every run.
