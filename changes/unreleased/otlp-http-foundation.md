Add the first-party R-53 journal-to-OTLP/HTTP protobuf foundation. Disabled
settings perform no file or network work; enabled exports contain only the
published `service.name`, `outcome`, and `trigger` attributes. A pinned real
OpenTelemetry Collector contract verifies the payload. In-app collector setup,
preview, and durable projection bookkeeping remain to be wired.
