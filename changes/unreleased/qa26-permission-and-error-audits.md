Audit the QA-26 states that were never covered: a failing destination, an
overdue export, a paused type, and the no-data browser and detail renderings
that a denied or partially authorised store produces. R-60 is why the
permission cases have no rendering of their own, so the no-data state is the
one that gets audited. Suppressing an accessibility finding now requires a
named cause with a tracking issue; a cause without a link fails the audit.

The matrix now also audits the locked and failed-authentication privacy gate,
public-destination confirmation, browser selection and review, diagnostic
sharing warning, successful/stale destinations, and the destination-change
banner. The audits exposed and fixed clipped lock copy, undersized selectable
status and confirmation rows, and insufficient cancel-button contrast.
