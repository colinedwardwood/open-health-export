### CompanionWire protocol + SinkCompanion

Length-prefixed HELLO / OFFER / RESUME / CHUNK / CHUNK_ACK / COMMIT / RECEIPT / REJECT
on Linux, no `Network` framework. Re-OFFER of a stored `batchID` returns the same RECEIPT
(O1). Dropped transfer resumes from the first missing chunk. `CompanionSink` is a
`DestinationSink` over an injectable byte pipe; live TLS PSK is still later.
