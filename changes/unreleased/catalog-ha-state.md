### Catalogue expansion and HA state JSON

The catalogue now includes active energy, distance, body mass, SpO₂ and respiratory rate with
Home Assistant classes that will not silently drop statistics (`energy` is `total_increasing`,
never `measurement`; SpO₂ is not `humidity`). HealthKit conversion asks for every catalogued
quantity type. HA state JSON is a non-retained `value` object with no UUID.
