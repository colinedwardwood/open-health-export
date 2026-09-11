A stranger can now build the app from a clean checkout the way the README says (QA-30).
The command ad-hoc-signs the simulator exporter and the Mac companion; it does not skip
signing, because that would only prove the sources compile. A physical iPhone still
needs a free personal team in Xcode — iOS 26 will not accept ad-hoc identity on the
device SDK, and HealthKit entitlements need a development certificate.

CI runs that same command on every push and pull request. Unit and integration tests
are now rejected if they subclass XCTestCase (QA-21). The release issue template names
the T0–T3, localisation, energy, and upgrade-from-previous gates (QA-31).
