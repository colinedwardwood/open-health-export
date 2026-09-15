HK-03 now permits the committed HealthKit identifier pin to come from a newer
Xcode than a supported CI runner. The pin was generated with Xcode 27, while
GitHub's `macos-26` image defaults to Xcode 26.6; exact set equality therefore
failed because the older header lacks three newer identifiers. CI now fails
when its live SDK contains an identifier absent from the pin, while the
existing coverage gate still requires every pinned identifier to be catalogued
or explicitly excluded. The pin records the Xcode and SDK that generated it.
