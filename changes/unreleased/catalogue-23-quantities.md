Expand the curated quantity catalogue from 10 to 23 families: cycling distance,
flights, basal energy, exercise and stand time, walking heart rate, HRV SDNN,
body and basal temperature, lean mass, dietary water, and systolic/diastolic
blood pressure. HealthKit conversion tests cover source-unit boundaries.
Blood glucose is corrected to the ratified canonical `mg/dL` unit and Home
Assistant's real `blood_glucose_concentration` device class.
Regenerate and re-pin the deterministic tier-zero corpus because catalogue
order is an input to its metric rotation.
