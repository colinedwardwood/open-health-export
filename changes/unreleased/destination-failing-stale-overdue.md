A failed destination stays failing through the stale window so the status line can
still name the last error (QA-14), and becomes overdue once that later deadline
passes. Deferred destinations still age into stale and overdue instead of freezing
on the last park reason.
