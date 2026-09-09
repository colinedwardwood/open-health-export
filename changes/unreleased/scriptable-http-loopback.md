QA-10's in-repo HTTP/1.1 loopback double now drives real `URLSessionHTTPTransport`
contracts for status, delay, chunked bodies, redirects that are not followed,
`Retry-After`, 401-then-success, gzip POST, and a mid-body reset — without SwiftNIO.
