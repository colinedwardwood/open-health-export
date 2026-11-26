# Launch success metrics

The app sends no analytics and the project forbids outbound telemetry (R-37), so every signal
below comes from Apple, GitHub, or people who contact support. None comes from inside the app.
This is the measurement plan that replaces the old free-app targets in PRD section 9.

Targets are TODO-owner: no target below is set because there is no baseline yet. Set each
before launch, write it in the target column, and do not change it afterwards.

## Metrics

| Metric | Source | Cadence | Target |
|---|---|---|---|
| Product page conversion (page views to first downloads) | App Store Connect, App Analytics | Weekly | TODO-owner |
| First downloads | App Store Connect | Weekly | TODO-owner |
| Unlock rate (purchases per 100 first downloads) | App Store Connect, Sales and Trends | Weekly | TODO-owner |
| Proceeds | App Store Connect, Payments and Financial Reports | Monthly | TODO-owner |
| Refund rate | Sales and Trends, refunds | Weekly | TODO-owner |
| Ratings and review count | App Store Connect | Weekly | TODO-owner |
| Crash-free sessions | Xcode Organizer (only from users who share analytics with developers) | Daily during rollout, then weekly | Halt criteria in `docs/runbooks/release-rollout.md` |
| Support contacts per 100 unlocks | `qa/support-log.md` over unlocks | Monthly | TODO-owner |
| Share of contacts that are "didn't export" | `qa/support-log.md` tags `background-overdue` plus `data-correctness` over all contacts | Monthly | TODO-owner |
| Time to first export | Self-reported by users who contact support or write reviews; count the answers, do not extrapolate | Monthly | TODO-owner |

Organizer and App Analytics cover only users who opted in to share with developers, and Apple
applies thresholds to small counts. Report them as a sample, never as the whole user base.

## Channel attribution

Give each channel its own App Store campaign link and record its `ct` value. Compare App Store
Connect campaign sources with GitHub traffic (Insights, Traffic) and downloads of any Mac
asset. Do not add tracking to the app, landing page or links beyond Apple's campaign parameter.

| Channel | `ct` value |
|---|---|
| Hacker News | `hn` |
| Home Assistant community forum | `ha-forum` |
| Reddit (self-hosted communities) | `reddit-selfhosted` |
| Mastodon | `mastodon` |
| Blog | `blog` |
| GitHub README / landing page | TODO-owner: choose a value if used |

## Review rhythm

- Weekly for the first 8 weeks after release, then monthly. TODO-owner: weekday.
- Write a note on day 7 and day 30 in the release issue: counts, what surprised you, what you
  will change. No user data, no quotes that identify anyone.
- A metric moving is a reason to look, not to add telemetry. If a number cannot be obtained
  without data leaving the device, drop the metric.

## Support tags

The tag list lives in [`../runbooks/support-triage.md`](../runbooks/support-triage.md#tags).

## Deliberately not used

GitHub stars, and any figure that requires in-app analytics, crash reporting or a first-party
server.
