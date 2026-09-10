POSIX TCP and the scriptable HTTP loopback no longer block Swift's cooperative
thread pool, and `URLSession` POSTs time out after 30s. Linux `swift test` was
able to stall for hours once Mosquitto spawn tests shared the runner with HTTP
contracts. linux-core now cancels superseded runs and bounds the test step.
Real-broker subprocess contracts run serially. Broker restart keeps
`Process.waitUntilExit()` off the cooperative pool on Darwin and uses a bounded
POSIX reap on Linux.
Container jobs select only the external-broker suite instead of rerunning every
local TLS and subprocess contract whose name contains `mosquittoQoS`.
NDJSON sidecar decoding uses correctly rounded `JSONDecoder` binary64 values,
avoiding Linux `JSONSerialization` drift on 17-digit canonical decimals.

Pinned HTTPS POSTs through the inner transport when tests fake it, and through a
pin-aware `URLSession` on the real stack.
