Expand the curated quantity catalogue from 10 to 26 families: cycling distance,
flights, basal energy, exercise and stand time, walking heart rate, HRV SDNN,
body and basal temperature, height, body fat, BMI, lean mass, dietary water,
and systolic/diastolic blood pressure. HealthKit conversion tests cover
source-unit boundaries.
Blood glucose is corrected to the ratified canonical `mg/dL` unit and Home
Assistant's real `blood_glucose_concentration` device class.
Regenerate and re-pin the deterministic tier-zero corpus because catalogue
order is an input to its metric rotation.
Active and basal energy deliberately omit Home Assistant's `energy` device
class, following the ratified synthesis: classifying calories into HA's Energy
dashboard is actively confusing.
Height's Home Assistant unit is `cm` while the wire canonical remains metres.
BMI omits `unit_of_measurement`. Body fat is percent, converted from HealthKit's
fraction the same way oxygen saturation is.
The Home Assistant discovery contract test is generated across the entire
catalogue and checks unique identifiers plus exact topic, unit, device-class
and state-class fields for every declaration.
