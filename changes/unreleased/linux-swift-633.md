### Linux CI uses the Swift 6.3 installer

The legacy setup action did not know Swift 6.3.3 and failed before compilation. Linux CI now
uses the Swiftly-backed v3 action pinned to an immutable commit.
