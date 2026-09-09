### Build-from-source and release gates

The Darwin PR job is explicitly named `build-from-source-clean` and builds the
package, generated iOS project, widget, UI tests, and Mac companion from a clean
checkout. A structured release issue requires version, QA, compliance,
provenance, stranger-test, roll-forward, and reviewer evidence before publish.
