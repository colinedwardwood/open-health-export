POSIX TCP and the scriptable HTTP loopback no longer block Swift's cooperative
thread pool, and `URLSession` POSTs time out after 30s. Linux `swift test` was
able to stall for hours once Mosquitto spawn tests shared the runner with HTTP
contracts. linux-core now cancels superseded runs and bounds the test step.
