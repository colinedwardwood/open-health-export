The nightly volume workflow now drives a real `ExportRun` over a generated T1
corpus slice, verifies that the run closes successfully with matching read and
acknowledged counts, and enforces the documented 100 MB peak-memory ceiling on
Linux.
