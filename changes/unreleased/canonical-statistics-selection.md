### Canonical cumulative aggregates use HealthKit statistics

Export and reconcile runs accept a `StatisticsSource`. Catalogue metrics whose
canonical value requires HealthKit now use that source, retain engine-owned
revision sequencing, and never silently fall back to summing raw samples. A
dirty day stays pending when the statistics adapter is unavailable.
