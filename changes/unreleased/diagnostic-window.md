Diagnostic bundles now retain the union of the latest 30 runs and every run
from the preceding 24 hours, rather than truncating high-frequency histories
at 200 rows. Journal rows persist wall-clock time and the closed error class;
the corruption-salvage reader applies the same union window and the bundle
includes allowlisted error classes while continuing to exclude arbitrary
detail text. The iOS diagnostics screen persists user-adjustable minimum-run
(1–100) and time-window (1–168 hours) controls and passes them to both the
salvage reader and bounded bundle assembler.
