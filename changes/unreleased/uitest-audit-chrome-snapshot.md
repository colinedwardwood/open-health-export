Accessibility-audit suppression classifies contrast findings against navigation
and tab chrome. That classification now snapshots bar and window frames once per
audit instead of querying XCTest on every finding, so RTL empty-browser audits
stay inside the XCTFuture deadline.
