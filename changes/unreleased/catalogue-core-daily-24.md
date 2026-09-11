Grow the curated quantity catalogue from 26 to 38 families with twelve
routine activity and environment types: swimming and wheelchair distance,
push and stroke counts, walking/running/cycling/stair-ascent speed, time in
daylight, environmental audio exposure, Apple Move Time, and physical effort.
Core Daily is now those twelve plus the existing named routine set (24),
still excluding every sensitive type (R-61 / R-66).
Cumulative totals among the new families use HealthKit statistics under
ADR-002. Physical effort uses HealthKit's kcal per kilogram-hour and omits Home
Assistant's `energy` device class, matching active and basal energy.
Environmental audio maps to HA `sound_pressure` in `dBA`.
Regenerate and re-pin the deterministic tier-zero corpus because catalogue
order is an input to its metric rotation.
