### First-party MQTT 3.1.1 publish-only

`MQTTCodec` + `SinkMQTT` are a separate product, not in `ExportCore` (ADR-0003). Packets:
CONNECT (CleanSession=1), CONNACK, PUBLISH, PUBACK, PINGREQ/PINGRESP, DISCONNECT. No
subscribe. Host allowlist via `mqtts`/`mqtt`. QoS 1 waits for PUBACK; QoS 0 is `unknown_ack`.
Transport is an injectable byte pipe — no third-party MQTT stack, no live TLS socket yet.
