### Restore-from-backup re-emits new HealthKit UUIDs

R-08's FIX-M05 witness keeps surviving census and `emitted_index`, then swaps
sample UUIDs the way a restored Health store does. Equal counts are a digest
mismatch, not a skip. The planner tombstones the absent identities so census
does not double, a trailing sweep repairs only the window, and full reconcile
repairs history without a second duplicate pass.
