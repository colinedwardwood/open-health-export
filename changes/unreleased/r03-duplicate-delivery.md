A scriptable HTTPS receiver keyed by `Idempotency-Key` converges on duplicate
delivery: two sends of the same batch leave one stored row and two delivery
attempts. Conflicting bytes for the same key are refused.
