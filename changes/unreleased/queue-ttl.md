Pending batches now carry a durable creation epoch. Foreground launch
transactionally evicts batches at the ratified seven-day TTL, records one gap
and tamper-evident ledger entry per batch, deletes payload files after commit,
re-seals the ledger head, and emits classified user-visible copy. Legacy rows
without a creation epoch are retained rather than guessed old.
