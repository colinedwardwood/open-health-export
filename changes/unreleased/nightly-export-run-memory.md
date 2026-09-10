The nightly volume workflow now drives a real `ExportRun` over a generated T1 corpus slice
— every metric in the slice, not one of them — verifies each run closes successfully with
matching read and acknowledged counts, and enforces the documented 100 MB peak-memory
ceiling on Linux by reading `VmHWM`.

Exporting a single type would have reduced a five-thousand-record slice to a couple of
hundred samples, which clears any ceiling worth declaring. macOS reports the peak as
unsupported rather than silently passing; the nightly job runs on Linux, where the bound
is enforced.
