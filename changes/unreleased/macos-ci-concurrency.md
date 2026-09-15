macOS CI now keeps one run per ref instead of preserving every intermediate
commit on `main`. The old per-SHA groups accumulated an unbounded queue: each
push retained five build jobs followed by six UI jobs with 90-minute ceilings,
so obsolete commits occupied all hosted macOS capacity while current work
waited. `macos-build` and the macOS-bearing R-84 matrix now cancel superseded
runs. The scheduled accessibility matrix also prevents overlapping manual and
scheduled runs.
