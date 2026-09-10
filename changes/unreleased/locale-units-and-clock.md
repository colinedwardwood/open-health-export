Display units now follow the device region by default, with the existing export/metric/US
overrides intact, and sample times follow the region's 12- or 24-hour convention with the
same kind of override (R-65).

Units resolve per measurement family rather than by a single metric/imperial switch,
because that switch gets the United Kingdom wrong twice — miles for distance, kilograms
for body mass — and cannot express that Germany reads mg/dL while Sweden reads mmol/L.
The clock convention is read from ICU's `j` skeleton rather than a region list, skipping
quoted literals so German's `HH 'Uhr'` is not mistaken for a 12-hour pattern.

The locale enters at the app layer only; every reading path takes an explicit policy, so
the matrix test drives all of them. Blood pressure no longer converts to kPa under metric
display, which was wrong for the countries it was meant to serve.
