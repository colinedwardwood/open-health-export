### Build-from-source and release gates

The Darwin PR job is explicitly named `build-from-source-clean` and builds the
package, generated iOS project, widget, UI tests, and Mac companion from a clean
checkout. A structured release issue requires version, QA, compliance,
provenance, stranger-test, roll-forward, and reviewer evidence before publish.
`policycheck` rejects sponsor/donor/premium gating and StoreKit references in
shipped source, build configuration, and entitlements. The README reports the
project as maintained and owner-directed without recruiting maintainers, while
`CONTINUITY.md` records the forkable path, owner-only credentials, exceptional
succession steps, and no-remote-control incident model.
