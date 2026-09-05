### HTTPS sink

`HTTPSSink` POSTs the same `ohe.wire/1` NDJSON file. Host allowlist and scheme checks run
before any transport call (R-32 step 1). A 2xx with no receipt JSON is `success` /
`status_only` (Home Assistant webhooks). A receipt body's `accepted` count is full ack
evidence. `URLSession` lives only in `NetEgress`. R-31 pin-on-first-use and the request
template are not in this slice.
