Add Apple privacy manifests to the iOS exporter, status widget, and Mac
companion. Each declares no tracking domains and no collected data. The policy
gate now fails for a missing or malformed manifest, any tracking/collection
declaration, any remote Swift package, or any binary SwiftPM target.
It also rejects direct `URLSession` and Network.framework primitives in app
targets, keeping user-requested egress behind reviewed NetEgress adapters. The
R-51 diagnostic canary includes a token, hostname, sample value and `Dexcom G7`
source name on every test run.
