Silence is now an in-app event, not only a widget and a notification (QA-15 / R-23).

A destination that succeeded and then stopped already aged to `overdue` on the status
line. That line is easy to miss. The same read now raises a banner that stays until a
later success moves the snapshot off overdue, without asking a server.
