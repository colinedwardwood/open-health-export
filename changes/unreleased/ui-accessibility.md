Expose stable accessibility identifiers for the destination status section and
its no-destinations state. The status widget now shares a tested deep-link
route with the app, which refreshes destination status without bypassing the
first-run disclosure. The data browser now exposes stable row, search, detail,
review, and empty-result identifiers, with XCUITests for empty search and
metric-detail navigation. CI also runs XCTest's accessibility audit over the
disclosure, main controls, empty search, and metric-detail screens, plus an
Accessibility Extra Extra Extra Large Dynamic Type launch.
