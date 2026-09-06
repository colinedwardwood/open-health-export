### Paired egress attempt ledger

Every transport call now writes a durable `attempt` ledger entry before the first byte can leave,
then writes exactly one `acknowledged`, `partial`, `unknown_ack`, or `failed` outcome with the same
attempt identifier. A failed replay remains queued, and an empty run writes no egress entry.
