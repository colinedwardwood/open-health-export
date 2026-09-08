Add Apple privacy manifests to the iOS exporter, status widget, and Mac
companion. Each declares no tracking domains and no collected data. The policy
gate now fails for a missing or malformed manifest, any tracking/collection
declaration, any remote Swift package, or any binary SwiftPM target.
