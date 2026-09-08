The iOS exporter now registers one `HKObserverQuery` per enabled core metric,
the documented fallback topology while R-71 G1 remains unresolved. Each
callback appends the wake ledger before work, serializes and coalesces
per-metric catch-up runs, and consumes its HealthKit completion receipt exactly
once on success, error, append failure, and deinitialization. Background
delivery uses metric-appropriate frequencies and is protected by a CI-checked
entitlement.

The application delegate now writes the launch wake record before fallible
bootstrap work, restores eligible observers during launch, and registers
refresh and processing tasks. Foreground activation and both background task
handlers record their distinct trigger before starting work; background
requests are resubmitted after completion and cancelled on expiration.
