Add per-destination W3C traceparent opt-in on HTTPS, off by default.
A header-plausible failure retries once without the header and disables
propagation; tracestate and baggage are never sent, and inbound headers
are never continued. MQTT still does not offer the option. The companion
wire field remains unwired.
