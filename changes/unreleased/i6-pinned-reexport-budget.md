Gap re-export batches now pin up to 25% of the queue cap (64 MB at the
256 MB production cap). Oldest-first eviction skips pinned batches so an
in-progress re-export is not the first thing dropped by live traffic.
Beyond that sub-budget, later re-export chunks join the normal class and
are paced by drain.
