Expose stable accessibility identifiers for the destination status section and
its no-destinations state. The status widget now shares a tested deep-link
route with the app, which refreshes destination status without bypassing the
first-run disclosure. The data browser now exposes stable row, search, detail,
review, and empty-result identifiers, with XCUITests for empty search and
metric-detail navigation. CI also runs XCTest's accessibility audit over the
disclosure, main controls, empty search, and metric-detail screens, plus an
Accessibility Extra Extra Extra Large Dynamic Type launch.
The data browser appears before advanced controls, uses Dynamic Type for
sensitivity labels, and keeps enabled text at system-primary contrast. UI
audits suppress only Xcode 26's known disabled-control contrast false positive,
tracked in issue #4; enabled contrast findings still fail.
Status, history, diagnostic, and Data-tab back controls wrap at Dynamic Type
sizes. Captions are not forced to 44 points at the default size, which had
pushed Status copy into the iPad tab fade. Browser Back stays a Button.
iPad window-bottom fade is named as the same tab-bar suppression as iPhone.
