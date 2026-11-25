# Runbooks

Procedures for the one person who operates this project. The design documents
(`docs/02-design/09-build-and-release.md`) describe a two-maintainer process; `MAINTAINERS.md`
says there is one owner and no deputy. These runbooks replace every "second maintainer" step
with something a solo owner can truthfully do, and say so where they do.

| Runbook | Use when |
|---|---|
| [`release-rollout.md`](release-rollout.md) | Cutting a release, watching the phased rollout, deciding to halt |
| [`incident.md`](incident.md) | Crash loop, data loss, wrong data, vulnerability, key or domain loss, iOS regression, data sent to the wrong place |
| [`advisory-publish.md`](advisory-publish.md) | Publishing or rotating the signed in-app advisory feed (once it is hosted) |
| [`support-triage.md`](support-triage.md) | Handling a support email, issue or App Store review |

User-facing companions: [`../support/known-issues.md`](../support/known-issues.md),
[`../support/sharing-crash-logs.md`](../support/sharing-crash-logs.md). Launch measurement:
[`../03-implementation/launch-metrics.md`](../03-implementation/launch-metrics.md).

## Solo substitutes for two-person controls

| Design step | Solo equivalent |
|---|---|
| Second maintainer verifies | Run the check from a second machine (or a fresh clone and a fresh login) and paste the output with a timestamp |
| Second maintainer approves | Cooling-off: finish the checklist, stop, and re-read it after at least 12 hours (24 hours for a security release) before pressing the button. Record both times |
| Two named compliance reviewers | Do not tick a box that names two reviewers. Record the owner's dated self-review and link any outside review actually obtained (TODO-owner: counsel review, #21) |
| Peer decision to halt | The halt criteria below were fixed in advance; applying them is not a judgment call |

## Rules for every runbook

- Write a timestamped log as you go (UTC). A line is: time, what you did, what you saw.
- Never put Health values, tokens, private hostnames or signing keys in a log, issue or email.
- Do not claim a step was done unless the log says so. An unticked box is honest; a
  falsely ticked one is not.
- Roll forward only. There is no remote configuration and no way to change an installed app
  (`CONTINUITY.md`). The tools are: pause the phased release, ship a fixed build, tell users.
- Each runbook is rehearsed once as a tabletop before 1.0 ships. Record the result in
  `qa/tabletops/<runbook>.md` (date, what was unclear, what changed). TODO-owner: not yet done.
