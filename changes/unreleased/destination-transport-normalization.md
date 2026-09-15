MQTT and HTTPS now normalize connection failures onto the same closed
`DestinationSendError` outcomes as the companion. Previously their adapters
leaked raw `StreamError`, `EgressError.transport`, or `URLError` values;
`DeliveryExecutor` classified every unknown error as transient and `ExportRun`
could not journal the specific destination outcome. HTTP status, Retry-After,
pin, and cancellation errors remain on their dedicated paths rather than being
flattened into network failures.
